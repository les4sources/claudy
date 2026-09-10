require "digest"
require Rails.root.join("lib/coda/parser")
require Rails.root.join("lib/coda/fingerprint")

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
  # 3. **Continuité applicative** — le fichier doit se raccorder à ce qui est
  #    déjà importé pour ce compte, soit bout à bout, soit par recouvrement. Le
  #    trou entre deux imports se voit là, et nulle part ailleurs.
  # 4. **Couverture du relevé** — une fois les lignes créées, le journal doit
  #    porter exactement les mouvements du relevé sur sa période, en nombre et en
  #    somme. C'est le filet sous la déduplication : une ligne prise à tort pour
  #    un doublon disparaîtrait sans lui, et rien ne le dirait.
  #
  # Le recouvrement n'est pas un cas tordu, c'est le cas NORMAL chez Triodos, qui
  # n'expose pas de relevés numérotés mais un export « mutations » libre : on
  # redemande la période en cours, et elle ressort en entier à chaque fois.
  #
  # L'import ne crée AUCUNE allocation : les lignes arrivent en attente, et c'est
  # un humain qui ventile. Un compte analytique deviné serait exactement le
  # défaut qu'on a éliminé du schéma.
  class Import < ServiceBase
    class Rejected < StandardError; end

    # `statements_skipped` vaut désormais toujours zéro : plus aucun relevé n'est
    # sauté, c'est le mouvement qui se déduplique. Le champ reste parce que l'API
    # publique le rend, et le retirer casserait un appelant pour rien.
    Report = Struct.new(:status, :statements, :entries_created, :entries_skipped,
                        :statements_skipped, :messages, :coda_import, keyword_init: true) do
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

      # Un dépôt qui n'a RIEN créé n'est pas un import : c'est une tentative. La
      # refuser au motif qu'elle a déjà eu lieu enferme celui qui la rejoue —
      # c'est exactement ce qui est arrivé au premier export Triodos, refusé pour
      # doublon puis impossible à redéposer une fois le refus corrigé. On la
      # reprend donc sur place. Un dépôt qui a créé des lignes, lui, garde son
      # refus : la déduplication le rendrait inoffensif, mais un second dépôt du
      # même fichier reste un geste qu'on signale plutôt qu'on exécute.
      if deja&.entries_count&.positive?
        return Report.new(status: "already_imported", statements: 0, entries_created: 0,
                          entries_skipped: 0, statements_skipped: 0, coda_import: deja,
                          messages: ["Ce fichier a déjà été déposé le #{I18n.l(deja.created_at.to_date)} " \
                                     "sous le nom « #{deja.filename} ». Rien n'a été créé."])
      end

      file = Parser.call(@content)
      accounts = resolve_accounts(file)
      validate!(file, accounts)

      entries_created = 0
      entries_skipped = 0
      coda_import = nil

      ApplicationRecord.transaction do
        coda_import = reprendre_ou_creer(deja, file, sha)

        file.statements.each do |statement|
          account = accounts.fetch(normalize(statement.account_number))

          coda_statement = CodaStatement.create!(
            coda_import: coda_import, cash_account: account,
            sequence_number: statement.sequence_number,
            period_year: (statement.new_balance_date || file.creation_date).year,
            old_balance_cents: statement.old_balance_cents,
            new_balance_cents: statement.new_balance_cents,
            old_balance_date: statement.old_balance_date,
            new_balance_date: statement.new_balance_date
          )

          created, ignored = create_entries(statement, account, coda_statement)
          coda_statement.update!(entries_count: created)
          entries_created += created
          entries_skipped += ignored

          verify_coverage!(statement, account)

          @messages << "Relevé #{statement.label} : #{created} ligne(s) créée(s)" +
                       (ignored.positive? ? ", #{ignored} déjà présente(s) et ignorée(s)." : ".")
        end

        coda_import.update!(statements_count: file.statements.size,
                            entries_count: entries_created,
                            report: @messages.join("\n"))
      end

      @messages.unshift("#{entries_created} ligne(s) créée(s) et #{entries_skipped} déjà présente(s), " \
                        "sur #{file.statements.size} relevé(s) lus.")
      Report.new(status: "imported", statements: file.statements.size, entries_created: entries_created,
                 entries_skipped: entries_skipped, statements_skipped: 0,
                 messages: @messages, coda_import: coda_import)
    end

    # Reprendre un dépôt stérile plutôt qu'en créer un second : l'unicité du
    # sha256 reste vraie, et l'historique ne se remplit pas de tentatives.
    def reprendre_ou_creer(deja, file, sha)
      attributs = { filename: @filename, creation_date: file.creation_date,
                    file_reference: file.file_reference, status: "imported",
                    whodunnit: @whodunnit, imported_at: Time.current, report: nil }

      return CodaImport.create!(sha256: sha, content: @content, **attributs) if deja.nil?

      # Ces relevés n'ont produit aucune ligne : ils ne portent aucun fait, et
      # les garder ferait buter le nouveau relevé sur l'unicité par fichier.
      CodaStatement.with_deleted { CodaStatement.where(coda_import_id: deja.id).delete_all }
      deja.update!(**attributs)
      @messages << "Dépôt du #{I18n.l(deja.created_at.to_date)} repris : il n'avait créé aucune ligne."
      deja
    end

    # Deux dépôts simultanés du même fichier passent tous deux le `find_by` : le
    # second heurterait l'index unique et rendrait une 500 au lieu d'un rapport.
    def already_imported_report(sha)
      deja = CodaImport.find_by(sha256: sha)
      Report.new(status: "already_imported", statements: 0, entries_created: 0,
                 entries_skipped: 0, statements_skipped: 0, coda_import: deja,
                 messages: ["Ce fichier a déjà été déposé sous le nom « #{deja&.filename} ». Rien n'a été créé."])
    end

    # Un compte inconnu REFUSE l'import. Créer un compte de trésorerie à la volée
    # reviendrait à décider seul qu'un compte bancaire existe, et avec quel
    # compte général de contrepartie — une décision qui n'appartient pas à un
    # import de fichier.
    def resolve_accounts(file)
      known = CashAccount.all.reject { |account| account.iban.blank? }
      manquants = []
      ambigus = []

      resolved = file.statements.each_with_object({}) do |statement, hash|
        key = normalize(statement.account_number)
        candidats = known.select { |account| same_account?(account.iban, statement.account_number) }

        manquants << statement.account_number if candidats.empty?
        ambigus << [statement.account_number, candidats.map(&:name)] if candidats.size > 1
        hash[key] = candidats.first
      end

      if manquants.any?
        raise Rejected,
              "Aucun compte de trésorerie ne porte le numéro de compte #{manquants.uniq.join(', ')}. " \
              "Crée-le dans Comptabilité > Entités avant de réimporter — un import ne crée pas de compte."
      end

      if ambigus.any?
        détail = ambigus.uniq.map { |numéro, noms| "#{numéro} → #{noms.join(' et ')}" }.join(" ; ")
        raise Rejected,
              "Le numéro de compte est porté par PLUSIEURS comptes de trésorerie : #{détail}. " \
              "Corrige les IBAN avant de réimporter — choisir à ta place serait pire que refuser."
      end

      resolved
    end

    # Un fichier CODA belge identifie le compte par sa BBAN — douze chiffres,
    # `523080601116` — parfois suivie du code devise. claudy, lui, stocke un
    # IBAN, `BE72 5230 8060 1116`. Les deux désignent le même compte, et une
    # comparaison de chaînes ne peut pas le voir : sans ce rapprochement, aucun
    # CODA belge réel n'entre, quel que soit le compte.
    #
    # La règle reste stricte : on compare les CHIFFRES du numéro de compte, et
    # l'IBAN doit s'y terminer. Une BBAN de douze chiffres ne se retrouve pas en
    # fin d'un autre IBAN par hasard, et un numéro trop court (moins de six
    # chiffres) ne rapproche rien du tout plutôt que de rapprocher au hasard.
    def same_account?(iban, coda_number)
      gauche = digits(iban)
      droite = digits(coda_number)
      return false if gauche.blank? || droite.length < 6

      gauche == droite || gauche.end_with?(droite)
    end

    def digits(value) = value.to_s.gsub(/\D/, "")

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
      file.statements.group_by { |s| normalize(s.account_number) }.each_value do |statements|
        # Le MÊME rapprochement que `resolve_accounts`, sinon le contrôle de
        # continuité se croit sans compte et se tait — exactement le contrôle
        # qu'on ne veut pas voir se taire.
        account = CashAccount.all.find { |a| same_account?(a.iban, statements.first.account_number) }
        next if account.nil?

        dernier = CodaStatement.last_for(account)
        next if dernier.nil?

        validate_continuity!(statements.first, dernier)
      end
    end

    # Deux raccords sont légitimes, et un seul l'était jusqu'ici.
    #
    # BOUT À BOUT — l'ancien solde du fichier reprend le dernier solde connu.
    # C'est le relevé numéroté classique, celui que la banque découpe pour nous.
    #
    # PAR RECOUVREMENT — le fichier repart plus tôt et rejoue une période déjà
    # importée. Il n'y a alors aucun solde à raccorder : ce qu'on vérifie est
    # qu'aucune période ne manque ENTRE les deux, c'est-à-dire que le fichier
    # commence au plus tard là où le journal s'arrête. La cohérence des montants
    # sur la partie commune, elle, est jugée par `verify_coverage!` sur les
    # lignes réelles, ce qui est à la fois plus fin et plus sûr qu'une
    # comparaison de soldes.
    #
    # Une reconstitution du solde à la date de reprise serait tentante et serait
    # fausse : un export pris en cours de journée arrête son solde au milieu des
    # mouvements du jour, et le lendemain la même date porte un autre solde. Le
    # contrôle refuserait alors un fichier parfaitement sain, ce qui est la
    # panne la plus coûteuse pour un contrôle — celle qui pousse à le désactiver.
    #
    # Refuser le recouvrement, comme on le faisait, revenait à exiger de la
    # banque un découpage qu'elle ne propose pas. Triodos n'expose pas de relevés
    # numérotés : on lui demande une période, il la rend en entier.
    # Le recouvrement se reconnaît à une date d'ouverture STRICTEMENT antérieure.
    # À date égale, on exige l'égalité des soldes : un fichier qui rouvre le
    # journal là où il s'arrête, sur un autre montant, ne recouvre rien — il
    # contredit. C'est le cas du relevé sauté par la banque, celui qu'aucun
    # contrôle intra-fichier ne voit.
    def validate_continuity!(premier, dernier)
      return if premier.old_balance_cents == dernier.new_balance_cents
      return if premier.old_balance_date && dernier.new_balance_date &&
                premier.old_balance_date < dernier.new_balance_date

      repere = dernier.new_balance_date ? " au #{I18n.l(dernier.new_balance_date)}" : ""

      raise Rejected,
            "Relevé #{premier.label} : son ancien solde (#{money(premier.old_balance_cents)}) ne suit pas " \
            "le dernier relevé importé #{dernier.label} (#{money(dernier.new_balance_cents)}), et sa période " \
            "ne le recouvre pas. Un relevé manque entre les deux. Redemande l'export à partir d'une date " \
            "antérieure#{repere} : le recouvrement, lui, est accepté. Rien n'a été importé."
    end

    # Après création, le journal doit porter EXACTEMENT le relevé sur sa période.
    #
    # C'est le filet sous la déduplication. Si une empreinte appariait deux
    # mouvements distincts, la ligne réelle ne serait jamais créée et rien
    # d'autre ne le dirait : les soldes du fichier, eux, resteraient justes.
    def verify_coverage!(statement, account)
      mouvements = statement.main_movements
      dates = mouvements.filter_map { |m| m.entry_date || statement.new_balance_date }
      return if dates.empty?

      nombre, somme = CashEntry.with_deleted do
        portee = CashEntry.where(cash_account_id: account.id, entry_date: dates.min..dates.max)
        [portee.count, portee.sum(:amount_cents)]
      end
      return if nombre == mouvements.size && somme == mouvements.sum(&:amount_cents)

      raise Rejected,
            "Relevé #{statement.label} : entre le #{I18n.l(dates.min)} et le #{I18n.l(dates.max)}, le journal " \
            "porterait #{nombre} ligne(s) pour #{money(somme)}, alors que le relevé en compte " \
            "#{mouvements.size} pour #{money(mouvements.sum(&:amount_cents))}. " \
            "Une ligne a été prise pour un doublon, ou le journal en portait déjà d'ailleurs. " \
            "Rien n'a été importé."
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

    def create_entries(statement, account, coda_statement)
      created = 0
      ignored = 0
      occurrences = Hash.new(0)

      statement.main_movements.each do |movement|
        champs = fingerprint_fields(movement, statement)
        empreinte_base = Fingerprint.digest(**champs)
        occurrences[empreinte_base] += 1
        empreinte = Fingerprint.call(occurrence: occurrences[empreinte_base], **champs)

        if CashEntry.with_deleted { CashEntry.exists?(cash_account_id: account.id, fingerprint: empreinte) }
          ignored += 1
          next
        end

        CashEntry.create!(
          **champs,
          cash_account: account,
          label: label_for(movement),
          fingerprint: empreinte,
          external_ref: external_ref(coda_statement, movement),
          statement_ref: coda_statement.label
        )
        created += 1
      end

      [created, ignored]
    end

    # Les champs qui composent l'empreinte sont EXACTEMENT ceux qu'on stocke sur
    # la ligne. C'est ce qui rend l'empreinte d'une ligne déjà importée
    # recalculable sans son fichier d'origine, et c'est ce dont vit la reprise de
    # l'existant : sans cette égalité, aucun journal déjà rempli ne pourrait
    # rejoindre le nouveau régime d'idempotence.
    def fingerprint_fields(movement, statement)
      {
        entry_date: movement.entry_date || statement.new_balance_date,
        value_date: movement.value_date,
        amount_cents: movement.amount_cents,
        counterparty_iban: movement.counterparty_account.presence,
        counterparty_name: movement.counterparty_name.presence,
        communication: movement.communication.presence,
        transaction_code: movement.transaction_code.presence
      }
    end

    # Une référence lisible qui pointe le relevé et la ligne DANS CE FICHIER-CI.
    # Elle ne porte plus l'idempotence — l'empreinte la porte — parce que le rang
    # d'un mouvement dans un export change d'un téléchargement à l'autre.
    # L'identifiant du relevé la rend unique sans lui demander d'être stable.
    def external_ref(coda_statement, movement)
      format("CODA-S%<statement>d-%<seq>04d-%<detail>04d",
             statement: coda_statement.id, seq: movement.sequence, detail: movement.detail)
    end

    def label_for(movement)
      [movement.counterparty_name.presence, movement.communication.presence]
        .compact.join(" — ").presence || "Mouvement #{movement.sequence}"
    end

    def normalize(value) = value.to_s.gsub(/\s+/, "").upcase

    def money(cents) = Money.new(cents, "EUR").format
  end
end
