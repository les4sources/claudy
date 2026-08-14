require "digest"
require Rails.root.join("lib/coda/parser")

module Coda
  # Importe un fichier CODA dans le journal de trésorerie (issue #181).
  #
  # L'ordre est imposé et non négociable : **parse intégral → validation → une
  # seule transaction**. Un fichier refusé ne laisse rien derrière lui. Un import
  # à moitié fait est pire qu'un import raté : personne ne sait plus ce qui est
  # entré, et le rejouer duplique la moitié qui était passée.
  #
  # Trois contrôles bloquants, et chacun répond à une panne réelle :
  #
  # 1. **Intra-relevé** — la somme des mouvements doit égaler nouveau solde moins
  #    ancien solde. Un relevé qui ne se referme pas sur lui-même est un fichier
  #    corrompu ou mal lu ; l'accepter, c'est injecter un écart qu'on cherchera
  #    des heures.
  # 2. **Chaînage entre relevés** — l'ancien solde d'un relevé doit égaler le
  #    nouveau solde du précédent. C'est ce contrôle qui attrape le relevé
  #    manquant quand l'export bancaire en saute un.
  # 3. **Continuité applicative** — l'ancien solde du premier relevé doit égaler
  #    le dernier nouveau solde déjà importé pour ce compte. Le trou entre deux
  #    imports se voit là, et nulle part ailleurs.
  #
  # L'import ne crée AUCUNE allocation : les lignes arrivent en attente, et c'est
  # un humain qui ventile. Un compte analytique deviné serait exactement le
  # défaut qu'on a éliminé du schéma.
  class Import < ServiceBase
    class Rejected < StandardError; end

    Report = Struct.new(:status, :statements, :entries_created, :statements_skipped,
                        :messages, :coda_import, keyword_init: true) do
      def to_text = messages.join("\n")
    end

    def initialize(content:, filename:, whodunnit: nil)
      @content = content.to_s
      @filename = filename
      @whodunnit = whodunnit
      @messages = []
    end

    def run
      catch_error(context: { filename: @filename }) { import }
    end

    def run!
      import
    rescue ActiveRecord::RecordNotUnique
      already_imported_report(Digest::SHA256.hexdigest(@content))
    end

    private

    def import
      sha = Digest::SHA256.hexdigest(@content)
      deja = CodaImport.find_by(sha256: sha)
      if deja
        return Report.new(status: "already_imported", statements: 0, entries_created: 0,
                          statements_skipped: 0, coda_import: deja,
                          messages: ["Ce fichier a déjà été déposé le #{I18n.l(deja.created_at.to_date)} " \
                                     "sous le nom « #{deja.filename} ». Rien n'a été créé."])
      end

      file = Parser.call(@content)
      accounts = resolve_accounts(file)
      validate!(file, accounts)

      entries_created = 0
      skipped = 0
      coda_import = nil

      ApplicationRecord.transaction do
        coda_import = CodaImport.create!(
          filename: @filename, sha256: sha, content: @content,
          creation_date: file.creation_date, file_reference: file.file_reference,
          status: "imported", whodunnit: @whodunnit, imported_at: Time.current
        )

        file.statements.each do |statement|
          account = accounts.fetch(normalize(statement.account_number))

          if already_imported?(statement, account)
            skipped += 1
            @messages << "Relevé #{statement.label} déjà importé — ignoré."
            next
          end

          coda_statement = CodaStatement.create!(
            coda_import: coda_import, cash_account: account,
            sequence_number: statement.sequence_number,
            period_year: (statement.new_balance_date || file.creation_date).year,
            old_balance_cents: statement.old_balance_cents,
            new_balance_cents: statement.new_balance_cents,
            old_balance_date: statement.old_balance_date,
            new_balance_date: statement.new_balance_date
          )

          created = create_entries(statement, account, coda_statement)
          coda_statement.update!(entries_count: created)
          entries_created += created
        end

        coda_import.update!(statements_count: file.statements.size - skipped,
                            entries_count: entries_created,
                            report: @messages.join("\n"))
      end

      @messages.unshift("#{entries_created} ligne(s) créée(s) sur #{file.statements.size} relevé(s) lus.")
      Report.new(status: "imported", statements: file.statements.size, entries_created: entries_created,
                 statements_skipped: skipped, messages: @messages, coda_import: coda_import)
    end

    # Deux dépôts simultanés du même fichier passent tous deux le `find_by` : le
    # second heurterait l'index unique et rendrait une 500 au lieu d'un rapport.
    def already_imported_report(sha)
      deja = CodaImport.find_by(sha256: sha)
      Report.new(status: "already_imported", statements: 0, entries_created: 0,
                 statements_skipped: 0, coda_import: deja,
                 messages: ["Ce fichier a déjà été déposé sous le nom « #{deja&.filename} ». Rien n'a été créé."])
    end

    # Un compte inconnu REFUSE l'import. Créer un compte de trésorerie à la volée
    # reviendrait à décider seul qu'un compte bancaire existe, et avec quel
    # compte général de contrepartie — une décision qui n'appartient pas à un
    # import de fichier.
    def resolve_accounts(file)
      known = CashAccount.all.index_by { |account| normalize(account.iban) }
      manquants = []

      resolved = file.statements.each_with_object({}) do |statement, hash|
        key = normalize(statement.account_number)
        account = known[key]
        manquants << statement.account_number if account.nil?
        hash[key] = account
      end

      if manquants.any?
        raise Rejected,
              "Aucun compte de trésorerie ne porte l'IBAN #{manquants.uniq.join(', ')}. " \
              "Crée-le dans Comptabilité > Entités avant de réimporter — un import ne crée pas de compte."
      end

      resolved
    end

    def validate!(file, _accounts)
      validate_trailer!(file)

      file.statements.each do |statement|
        ecart = statement.movements_total_cents - statement.balance_delta_cents
        next if ecart.zero?

        raise Rejected,
              "Relevé #{statement.label} : la somme des mouvements " \
              "(#{money(statement.movements_total_cents)}) ne correspond pas à la variation de solde " \
              "(#{money(statement.balance_delta_cents)}). Écart de #{money(ecart)}. " \
              "Rien n'a été importé."
      end

      # Chaînage à l'intérieur du fichier, compte par compte.
      file.statements.group_by { |s| normalize(s.account_number) }.each_value do |statements|
        statements.each_cons(2) do |precedent, suivant|
          next if suivant.old_balance_cents == precedent.new_balance_cents

          raise Rejected,
                "Relevé #{suivant.label} : son ancien solde (#{money(suivant.old_balance_cents)}) ne suit pas " \
                "le nouveau solde du relevé précédent (#{money(precedent.new_balance_cents)}). " \
                "Il manque probablement un relevé entre les deux. Rien n'a été importé."
        end
      end

      # Continuité avec ce qui est déjà en base.
      file.statements.group_by { |s| normalize(s.account_number) }.each do |key, statements|
        account = CashAccount.find_by(iban: statements.first.account_number) ||
                  CashAccount.all.find { |a| normalize(a.iban) == key }
        next if account.nil?

        dernier = CodaStatement.last_for(account)
        next if dernier.nil?

        # Le premier relevé RÉELLEMENT nouveau, pas le premier du fichier : un
        # relevé déjà importé, placé en tête, servirait sinon de pont et ferait
        # entrer le suivant sans que son ancien solde soit confronté à la base.
        premier = statements.find { |s| !already_imported?(s, account) }
        next if premier.nil?
        next if premier.old_balance_cents == dernier.new_balance_cents

        raise Rejected,
              "Relevé #{premier.label} : son ancien solde (#{money(premier.old_balance_cents)}) ne suit pas " \
              "le dernier relevé importé #{dernier.label} (#{money(dernier.new_balance_cents)}). " \
              "Un relevé manque entre les deux. Rien n'a été importé."
      end
    end

    # L'enregistrement de fin porte le nombre d'enregistrements et les totaux
    # débit / crédit. Les lire sans les vérifier laisse passer le cas où un
    # débit et un crédit fabriqués se compensent : les trois autres contrôles
    # sont satisfaits, et deux fausses lignes entrent quand même.
    def validate_trailer!(file)
      mouvements = file.statements.flat_map(&:main_movements)
      debits = mouvements.select { |m| m.amount_cents.negative? }.sum { |m| m.amount_cents.abs }
      credits = mouvements.select { |m| m.amount_cents.positive? }.sum(&:amount_cents)

      if file.debit_total_cents != debits
        raise Rejected,
              "Total des débits annoncé par le fichier : #{money(file.debit_total_cents)}, " \
              "somme des mouvements lus : #{money(debits)}. Rien n'a été importé."
      end

      return if file.credit_total_cents == credits

      raise Rejected,
            "Total des crédits annoncé par le fichier : #{money(file.credit_total_cents)}, " \
            "somme des mouvements lus : #{money(credits)}. Rien n'a été importé."
    end

    def already_imported?(statement, account)
      annee = (statement.new_balance_date || Date.current).year
      CodaStatement.exists?(cash_account_id: account.id, period_year: annee,
                            sequence_number: statement.sequence_number)
    end

    def create_entries(statement, account, coda_statement)
      created = 0

      statement.main_movements.each do |movement|
        reference = external_ref(coda_statement, movement)
        next if CashEntry.exists?(cash_account_id: account.id, external_ref: reference)

        CashEntry.create!(
          cash_account: account,
          entry_date: movement.entry_date || statement.new_balance_date,
          value_date: movement.value_date,
          amount_cents: movement.amount_cents,
          label: label_for(movement),
          counterparty_name: movement.counterparty_name.presence,
          counterparty_iban: movement.counterparty_account.presence,
          communication: movement.communication.presence,
          transaction_code: movement.transaction_code.presence,
          external_ref: reference,
          statement_ref: coda_statement.label
        )
        created += 1
      end

      created
    end

    # Stable d'un import à l'autre : c'est ce qui rend le troisième niveau
    # d'idempotence effectif même si la banque renvoie le même relevé dans un
    # fichier différent.
    def external_ref(coda_statement, movement)
      format("CODA:%<year>d:%<statement>s:%<seq>04d:%<detail>04d",
             year: coda_statement.period_year, statement: coda_statement.sequence_number,
             seq: movement.sequence, detail: movement.detail)
    end

    def label_for(movement)
      [movement.counterparty_name.presence, movement.communication.presence]
        .compact.join(" — ").presence || "Mouvement #{movement.sequence}"
    end

    def normalize(value) = value.to_s.gsub(/\s+/, "").upcase

    def money(cents) = Money.new(cents, "EUR").format
  end
end
