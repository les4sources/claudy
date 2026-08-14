# Comptabilité en partie double — seeds et vérifications (issue #177, lot B).
#
# Les trois rakes de vérification sont le filet du lot : ils doivent sortir vides
# et en `exit 0`. Une comptabilité qui se contredit toute seule ne vaut que si
# quelqu'un l'écoute — ces tâches sont cette écoute.
namespace :accounting do
  desc "Seed du référentiel — entités, plan comptable PCMN réduit, exercice courant. Idempotent"
  task seed_reference: :environment do
    created = Hash.new(0)

    entities = [
      { name: "Fondation Les 4 Sources", form: "foundation", vat_regime: "exempt" },
      { name: "Société simple immobilière", form: "simple_company", vat_regime: "exempt" },
      { name: "Marco & Vespucci SRL", form: "srl", vat_regime: "subject" }
    ]

    entities.each do |attributes|
      entity = LegalEntity.find_or_initialize_by(name: attributes[:name])
      created[:entities] += 1 if entity.new_record?
      entity.assign_attributes(attributes)
      entity.save!
    end

    # PCMN belge réduit. C'est un référentiel de DÉPART, pas une vérité : le
    # plan comptable réel de la Fondation appartient au comptable, et cet écran
    # est éditable précisément pour qu'il le corrige sans migration.
    chart = [
      # Classe 1 — capitaux propres
      ["100000", "Fonds de la fondation", 1, "equity"],
      ["130000", "Réserves", 1, "equity"],
      ["140000", "Résultat reporté", 1, "equity"],
      # Classe 2 — immobilisations
      ["221000", "Constructions", 2, "asset"],
      ["230000", "Installations, machines et outillage", 2, "asset"],
      ["240000", "Mobilier et matériel roulant", 2, "asset"],
      ["241000", "Matériel informatique", 2, "asset"],
      # Classe 4 — créances et dettes
      ["400000", "Clients", 4, "asset", true],
      ["411000", "TVA à récupérer", 4, "asset"],
      ["416000", "Créances diverses", 4, "asset", true],
      ["440000", "Fournisseurs", 4, "liability", true],
      ["451000", "TVA à payer", 4, "liability"],
      ["455000", "Rémunérations à payer", 4, "liability"],
      ["489000", "Comptes courants sourciers", 4, "asset", true],
      # Classe 5 — trésorerie
      ["550000", "Banque", 5, "asset", true],
      ["551000", "Stripe", 5, "asset", true],
      ["570000", "Caisse", 5, "asset", true],
      [GeneralAccount::INTERNAL_TRANSFER_CODE, "Virements internes", 5, "asset", true],
      # Classe 6 — charges
      ["600000", "Achats de marchandises (bar, cellier, épicerie)", 6, "expense"],
      ["601000", "Achats d'approvisionnements", 6, "expense"],
      ["610000", "Services et biens divers", 6, "expense"],
      ["611000", "Entretien et réparations", 6, "expense"],
      ["612000", "Énergie", 6, "expense"],
      ["613000", "Honoraires", 6, "expense"],
      ["614000", "Assurances", 6, "expense"],
      ["615000", "Frais de bureau et télécommunications", 6, "expense"],
      ["618000", "Frais bancaires et commissions", 6, "expense"],
      ["620000", "Rémunérations", 6, "expense"],
      ["630000", "Amortissements", 6, "expense"],
      ["640000", "Charges diverses", 6, "expense"],
      # Classe 7 — produits
      ["700000", "Locations d'hébergement", 7, "revenue"],
      ["700100", "Locations de salles", 7, "revenue"],
      ["700200", "Repas", 7, "revenue"],
      ["700300", "Bar et cellier", 7, "revenue"],
      ["700400", "Activités", 7, "revenue"],
      ["701000", "Formations", 7, "revenue"],
      ["730000", "Dons et mécénat", 7, "revenue"],
      ["740000", "Subsides", 7, "revenue"],
      ["750000", "Produits financiers", 7, "revenue"]
    ]

    chart.each do |code, name, klass, nature, reconcilable|
      account = GeneralAccount.find_or_initialize_by(code: code)
      created[:accounts] += 1 if account.new_record?
      account.assign_attributes(name: name, klass: klass, nature: nature,
                                reconcilable: reconcilable.present?)
      account.save!
    end

    # L'exercice civil courant, ouvert. La borne calendaire n'est pas un choix
    # de gouvernance ; le bilan d'ouverture, lui, en est un et reste vide.
    year = Date.current.year
    LegalEntity.find_each do |entity|
      fiscal = FiscalYear.find_or_initialize_by(legal_entity: entity, starts_on: Date.new(year, 1, 1))
      created[:fiscal_years] += 1 if fiscal.new_record?
      fiscal.assign_attributes(ends_on: Date.new(year, 12, 31), status: "open")
      fiscal.save!
    end

    puts "[accounting:seed_reference] #{created[:entities]} entité(s), #{created[:accounts]} compte(s), " \
         "#{created[:fiscal_years]} exercice(s) créé(s). Total : #{LegalEntity.count} entités, " \
         "#{GeneralAccount.count} comptes, #{FiscalYear.count} exercices."
  end

  desc "Vérifie l'équilibre et la cohérence des écritures — exit 1 si écart"
  task verify_double_entry: :environment do
    ecarts = []

    JournalEntry.unscoped.includes(:journal_lines, :fiscal_year).find_each do |entry|
      lines = entry.journal_lines.to_a

      if lines.empty?
        ecarts << "#{entry.reference} : écriture sans ligne"
        next
      end

      debits = lines.sum(&:debit_cents)
      credits = lines.sum(&:credit_cents)
      ecarts << "#{entry.reference} : déséquilibre — #{debits} au débit, #{credits} au crédit" if debits != credits

      lines.each do |line|
        both = line.debit_cents.positive? && line.credit_cents.positive?
        neither = line.debit_cents.zero? && line.credit_cents.zero?
        negative = line.debit_cents.negative? || line.credit_cents.negative?
        next unless both || neither || negative

        ecarts << "#{entry.reference} : ligne #{line.id} à double sens, vide ou négative"
      end

      unless entry.fiscal_year&.covers?(entry.entry_date)
        ecarts << "#{entry.reference} : date #{entry.entry_date} hors de son exercice"
      end
    end

    report("verify_double_entry", ecarts, "#{JournalEntry.unscoped.count} écriture(s) vérifiée(s)")
  end

  desc "Vérifie qu'aucun numéro ne manque par journal, exercice et entité — exit 1 si trou"
  task verify_numbering: :environment do
    ecarts = []

    JournalEntry.unscoped.group(:fiscal_year_id, :journal).count.each_key do |fiscal_year_id, journal|
      numeros = JournalEntry.unscoped
                            .where(fiscal_year_id: fiscal_year_id, journal: journal)
                            .pluck(:number).sort
      attendus = (1..numeros.max).to_a
      manquants = attendus - numeros
      next if manquants.empty?

      fiscal = FiscalYear.unscoped.find(fiscal_year_id)
      ecarts << "#{fiscal.legal_entity.name} #{fiscal.label} #{journal} : numéro(s) manquant(s) " \
                "#{manquants.join(', ')}"
    end

    report("verify_numbering", ecarts, "séquences continues")
  end

  desc "Vérifie que les virements internes se soldent à zéro par exercice — exit 1 si écart"
  task verify_internal_transfers: :environment do
    ecarts = []
    compte = GeneralAccount.find_by(code: GeneralAccount::INTERNAL_TRANSFER_CODE)

    if compte.nil?
      puts "[accounting:verify_internal_transfers] Compte #{GeneralAccount::INTERNAL_TRANSFER_CODE} absent — " \
           "lance d'abord accounting:seed_reference."
      exit 1
    end

    FiscalYear.unscoped.find_each do |fiscal|
      lignes = JournalLine.unscoped
                          .joins(:journal_entry)
                          .where(general_account_id: compte.id, journal_entries: { fiscal_year_id: fiscal.id })
      solde = lignes.sum(:debit_cents) - lignes.sum(:credit_cents)
      next if solde.zero?

      ecarts << "#{fiscal.legal_entity.name} #{fiscal.label} : virements internes soldés à #{solde} au lieu de 0"
    end

    report("verify_internal_transfers", ecarts, "#{FiscalYear.unscoped.count} exercice(s) vérifié(s)")
  end

  def report(name, ecarts, resume)
    if ecarts.empty?
      puts "[accounting:#{name}] Aucun écart — #{resume}."
    else
      puts "[accounting:#{name}] #{ecarts.size} écart(s) :"
      ecarts.each { |e| puts "  ! #{e}" }
      exit 1
    end
  end
end
