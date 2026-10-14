require "base64"
require "digest"
require Rails.root.join("lib/beobank/parser")
require Rails.root.join("lib/coda/fingerprint")

module Beobank
  # Importe l'export Excel de Beobank dans le journal de trésorerie
  # (Michael, 2026-10-13).
  #
  # Beobank ne propose pas de CODA pour le compte de la SRL ; son classeur
  # « Vos comptes » est le seul export complet. Le service suit l'ordre et les
  # contrôles de `Coda::Import`, pour les mêmes raisons : **parse intégral →
  # validation → une seule transaction**, et un fichier refusé ne laisse rien.
  #
  # 1. **Intra-relevé** — fait par le parseur : le cumul des montants doit
  #    retomber, jour après jour, sur la colonne Solde de Beobank.
  # 2. **Continuité** — le fichier doit recouvrir la dernière ligne déjà connue
  #    du compte. Un export qui commence après elle laisse un trou.
  # 3. **Couverture** — une fois les lignes créées, le journal doit porter
  #    exactement les mouvements du fichier sur sa période, en nombre et en
  #    somme. C'est le filet sous la déduplication.
  #
  # La déduplication ne peut pas se fier à l'empreinte STOCKÉE : les lignes
  # Beobank déjà en base sont entrées par l'API, sans empreinte, ou à la main.
  # Elle recalcule donc l'empreinte des lignes existantes à partir de leurs
  # colonnes (c'est pour ça que `Coda::Fingerprint` ne retient que des champs
  # stockés), puis, pour ce qui reste, reconnaît une ligne sans empreinte par
  # sa date et son montant. La couverture vérifie que rien ne s'est apparié à
  # tort.
  #
  # Le dépôt est gardé comme un `CodaImport` (contenu en base64), pour qu'il
  # apparaisse dans le même historique que les fichiers CODA.
  class Import < ServiceBase
    class Rejected < StandardError; end

    Report = Coda::Import::Report

    def initialize(content:, filename:, whodunnit: nil)
      @content = content.to_s.b
      @filename = filename
      @whodunnit = whodunnit
      @messages = []
    end

    def run!
      import
    rescue ActiveRecord::RecordNotUnique
      deja = CodaImport.find_by(sha256: sha)
      Report.new(status: "already_imported", statements: 0, entries_created: 0, entries_skipped: 0,
                 statements_skipped: 0, coda_import: deja,
                 messages: ["Ce fichier a déjà été déposé sous le nom « #{deja&.filename} ». Rien n'a été créé."])
    end

    private

    def sha = @sha ||= Digest::SHA256.hexdigest(@content)

    def import
      deja = CodaImport.find_by(sha256: sha)
      if deja&.entries_count&.positive?
        return Report.new(status: "already_imported", statements: 0, entries_created: 0,
                          entries_skipped: 0, statements_skipped: 0, coda_import: deja,
                          messages: ["Ce fichier a déjà été déposé le #{I18n.l(deja.created_at.to_date)} " \
                                     "sous le nom « #{deja.filename} ». Rien n'a été créé."])
      end

      export = Parser.call(@content)
      accounts = export.statements.to_h { |statement| [statement.iban, resolve_account(statement)] }
      export.statements.each { |statement| validate_continuity!(statement, accounts.fetch(statement.iban)) }

      created_total = 0
      skipped_total = 0
      coda_import = nil

      ApplicationRecord.transaction do
        coda_import = reprendre_ou_creer(deja, export)

        export.statements.each do |statement|
          account = accounts.fetch(statement.iban)
          coda_statement = CodaStatement.create!(
            coda_import: coda_import, cash_account: account, sequence_number: "xlsx",
            period_year: (statement.new_balance_date || export.export_date || Date.current).year,
            old_balance_cents: statement.old_balance_cents, new_balance_cents: statement.new_balance_cents,
            old_balance_date: statement.old_balance_date, new_balance_date: statement.new_balance_date
          )

          created, skipped, manual = create_entries(statement, account, coda_statement)
          coda_statement.update!(entries_count: created)
          verify_coverage!(statement, account)

          created_total += created
          skipped_total += skipped
          @messages << "#{statement.label} : #{created} ligne(s) créée(s)" +
                       (skipped.positive? ? ", #{skipped} déjà présente(s) et ignorée(s)" : "") +
                       (manual.positive? ? ", dont #{manual} reconnue(s) par leur date et leur montant" : "") +
                       "."
        end

        coda_import.update!(statements_count: export.statements.size, entries_count: created_total,
                            report: @messages.join("\n"))
      end

      @messages.unshift("#{created_total} ligne(s) créée(s) et #{skipped_total} déjà présente(s), " \
                        "sur #{export.statements.size} compte(s) lu(s).")
      Report.new(status: "imported", statements: export.statements.size, entries_created: created_total,
                 entries_skipped: skipped_total, statements_skipped: 0, messages: @messages,
                 coda_import: coda_import)
    end

    def reprendre_ou_creer(deja, export)
      attributs = { filename: @filename, creation_date: export.export_date, file_reference: "Beobank (Excel)",
                    status: "imported", whodunnit: @whodunnit, imported_at: Time.current, report: nil,
                    content: Base64.strict_encode64(@content) }

      return CodaImport.create!(sha256: sha, **attributs) if deja.nil?

      CodaStatement.with_deleted { CodaStatement.where(coda_import_id: deja.id).delete_all }
      deja.update!(**attributs)
      @messages << "Dépôt du #{I18n.l(deja.created_at.to_date)} repris : il n'avait créé aucune ligne."
      deja
    end

    # Comme pour le CODA, un compte inconnu ou ambigu REFUSE l'import : créer un
    # compte de trésorerie est une décision, pas un effet de bord d'un fichier.
    def resolve_account(statement)
      candidats = CashAccount.all.select { |account| normalize_iban(account.iban) == statement.iban }

      if candidats.empty?
        raise Rejected,
              "Aucun compte de trésorerie ne porte l'IBAN #{statement.iban}. " \
              "Ajoute cet IBAN au bon compte de trésorerie (connecteur Claude, outil compte_tresorerie) avant de réimporter — un import ne crée pas de compte."
      end
      if candidats.size > 1
        raise Rejected,
              "L'IBAN #{statement.iban} est porté par PLUSIEURS comptes de trésorerie " \
              "(#{candidats.map(&:name).join(' et ')}). Corrige les IBAN avant de réimporter."
      end

      candidats.first
    end

    def normalize_iban(value) = value.to_s.gsub(/[^A-Za-z0-9]/, "").upcase

    # Le fichier doit commencer au plus tard le jour de la dernière ligne déjà
    # connue du compte : sinon les mouvements d'entre-deux manqueraient sans
    # que rien ne le dise.
    def validate_continuity!(statement, account)
      premier = statement.old_balance_date
      return if premier.nil?

      derniere = CashEntry.with_deleted { CashEntry.where(cash_account_id: account.id).maximum(:entry_date) }
      return if derniere.nil? || premier <= derniere

      raise Rejected,
            "#{statement.label} : le fichier commence le #{I18n.l(premier)}, mais le journal s'arrête " \
            "le #{I18n.l(derniere)}. Les mouvements d'entre-deux manqueraient. Redemande à Beobank un export " \
            "qui commence au plus tard le #{I18n.l(derniere)} : le recouvrement, lui, est accepté. " \
            "Rien n'a été importé."
    end

    def create_entries(statement, account, coda_statement)
      dates = statement.movements.map(&:entry_date)
      existantes = CashEntry.with_deleted do
        CashEntry.where(cash_account_id: account.id, entry_date: dates.min..dates.max).to_a
      end

      # Empreinte de base → lignes déjà en base qui la portent, recalculée sur
      # leurs colonnes. Chaque mouvement du fichier en consomme une.
      par_empreinte = existantes.group_by { |entry| Coda::Fingerprint.digest(**stored_fields(entry)) }
      restants = []
      deja = 0
      occurrences = Hash.new(0)

      statement.movements.each do |movement|
        champs = fields(movement)
        base = Coda::Fingerprint.digest(**champs)
        occurrences[base] += 1

        if (entry = par_empreinte[base]&.shift)
          existantes.delete(entry)
          deja += 1
        else
          restants << [movement, champs, occurrences[base]]
        end
      end

      # Une ligne entrée sans empreinte — saisie à la main, ou reprise par l'API
      # avant l'import Excel — ne porte pas toujours le libellé ou la date de
      # valeur exacts de la banque : on la reconnaît à sa date et à son montant.
      # Une ligne qui a une empreinte vient d'un import et s'apparie exactement
      # ou pas du tout. La couverture vérifie ensuite le nombre et la somme sur
      # toute la période.
      sans_empreinte = existantes.select { |entry| entry.fingerprint.blank? }
      manuelles = 0
      created = 0

      restants.each do |movement, champs, occurrence|
        if (entry = sans_empreinte.find { |e| e.entry_date == movement.entry_date && e.amount_cents == movement.amount_cents })
          sans_empreinte.delete(entry)
          manuelles += 1
          deja += 1
          next
        end

        CashEntry.create!(
          **champs,
          cash_account: account,
          label: movement.label.presence || "Mouvement ligne #{movement.row}",
          fingerprint: unused_fingerprint(account, champs, occurrence),
          external_ref: format("BEOBANK-S%<statement>d-%<row>04d", statement: coda_statement.id, row: movement.row),
          statement_ref: "Beobank #{statement.new_balance_date&.strftime('%d/%m/%Y')}".strip
        )
        created += 1
      end

      [created, deja, manuelles]
    end

    # Le rang d'occurrence du fichier peut déjà être pris par une ligne CODA ou
    # un import précédent dont l'empreinte stockée n'a pas été appariée (libellé
    # retouché depuis) ; l'index unique refuserait alors la ligne. On prend le
    # premier rang libre.
    def unused_fingerprint(account, champs, occurrence)
      rang = occurrence
      loop do
        empreinte = Coda::Fingerprint.call(occurrence: rang, **champs)
        pris = CashEntry.with_deleted { CashEntry.exists?(cash_account_id: account.id, fingerprint: empreinte) }
        return empreinte unless pris

        rang += 1
      end
    end

    # Les champs de l'empreinte sont ceux qu'on stocke, comme pour le CODA. Les
    # lignes Beobank déjà en base portent le libellé de la banque dans
    # `communication`, sans contrepartie : on les écrit de la même façon.
    def fields(movement)
      { entry_date: movement.entry_date, value_date: movement.value_date, amount_cents: movement.amount_cents,
        counterparty_iban: nil, counterparty_name: nil, communication: movement.label.presence,
        transaction_code: nil }
    end

    def stored_fields(entry)
      { entry_date: entry.entry_date, value_date: entry.value_date, amount_cents: entry.amount_cents,
        counterparty_iban: entry.counterparty_iban.presence, counterparty_name: entry.counterparty_name.presence,
        communication: entry.communication.to_s.unicode_normalize(:nfc).presence,
        transaction_code: entry.transaction_code.presence }
    end

    def verify_coverage!(statement, account)
      dates = statement.movements.map(&:entry_date)
      return if dates.empty?

      nombre, somme = CashEntry.with_deleted do
        portee = CashEntry.where(cash_account_id: account.id, entry_date: dates.min..dates.max)
        [portee.count, portee.sum(:amount_cents)]
      end
      attendu = statement.movements_total_cents
      return if nombre == statement.movements.size && somme == attendu

      raise Rejected,
            "#{statement.label} : entre le #{I18n.l(dates.min)} et le #{I18n.l(dates.max)}, le journal " \
            "porterait #{nombre} ligne(s) pour #{money(somme)}, alors que le fichier en compte " \
            "#{statement.movements.size} pour #{money(attendu)}. Une ligne du journal ne correspond à aucun " \
            "mouvement du fichier (saisie à la main avec une autre date ou un autre montant ?), ou une ligne " \
            "a été prise pour un doublon. Rien n'a été importé."
    end

    def money(cents) = Money.new(cents, "EUR").format
  end
end
