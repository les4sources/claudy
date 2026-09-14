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
      [GeneralAccount::INTER_ENTITY_CODE, "Compte courant inter-entités", 4, "asset", true],
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
      [GeneralAccount::REVENUE_SHARE_CODE, "Reversements aux propriétaires", 6, "expense"],
      ["620000", "Rémunérations", 6, "expense"],
      ["630000", "Amortissements", 6, "expense"],
      ["640000", "Charges diverses", 6, "expense"],
      [GeneralAccount::CASH_DIFFERENCE_CODE, "Écarts de caisse", 6, "expense"],
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

    # Correspondance catégorie de devis → compte de recette. Le compte est
    # mécanique ; le pôle reste vide, c'est une décision du collectif.
    mappings = {
      "lodging" => "700000",
      "spaces" => "700100",
      "meals" => "700200",
      "camping" => "700000",
      "van" => "700000",
      "terrace" => "700000",
      "hamac" => "700000",
      "experiences" => "700400"
    }
    mappings.each do |category, code|
      compte = GeneralAccount.find_by(code: code)
      next if compte.nil?

      mapping = RevenueMapping.find_or_initialize_by(category: category)
      created[:mappings] += 1 if mapping.new_record?
      mapping.general_account = compte
      mapping.save!
    end

    puts "[accounting:seed_reference] #{created[:entities]} entité(s), #{created[:accounts]} compte(s), " \
         "#{created[:fiscal_years]} exercice(s) créé(s). Total : #{LegalEntity.count} entités, " \
         "#{GeneralAccount.count} comptes, #{FiscalYear.count} exercices, " \
         "#{RevenueMapping.count} correspondances de recette."
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

  desc "Vérifie la cohérence des affectations de trésorerie — exit 1 si écart"
  task verify_allocations: :environment do
    ecarts = []

    # Le scope par défaut, pas `unscoped` : une ligne de trésorerie ne se
    # supprime pas (le modèle le refuse), donc tout ce qui porte un `deleted_at`
    # a été retiré à la main et ne fait plus partie du grand livre vivant.
    CashEntry.includes(:cash_allocations, :journal_entries).find_each do |entry|
      affecte = entry.cash_allocations.sum(&:amount_cents)

      if affecte.abs > entry.amount_cents.abs
        ecarts << "Ligne ##{entry.id} (#{entry.label}) : sur-affectée — #{affecte} pour #{entry.amount_cents}"
      end

      if entry.status == "allocated" && !entry.posted?
        ecarts << "Ligne ##{entry.id} (#{entry.label}) : marquée affectée mais sans écriture comptable"
      end

      if entry.status == "allocated" && affecte != entry.amount_cents
        ecarts << "Ligne ##{entry.id} (#{entry.label}) : marquée affectée alors qu'il reste #{entry.amount_cents - affecte}"
      end

      if entry.status != "allocated" && entry.posted?
        ecarts << "Ligne ##{entry.id} (#{entry.label}) : #{entry.status} alors qu'une écriture la référence encore"
      end

      entry.cash_allocations.each do |allocation|
        ecarts << "Ligne ##{entry.id} : allocation #{allocation.id} sans entité juridique" if allocation.legal_entity_id.blank?

        if allocation.amount_cents.positive? != entry.amount_cents.positive?
          ecarts << "Ligne ##{entry.id} : allocation #{allocation.id} de sens contraire au mouvement"
        end
      end
    end

    # Une écriture de trésorerie sans sa ligne source serait un montant qui
    # n'est rattaché à aucun mouvement réel.
    JournalEntry.unscoped.where(journal: %w[bank cash], source_type: "CashEntry").find_each do |entry|
      next if CashEntry.unscoped.exists?(id: entry.source_id)

      ecarts << "Écriture #{entry.reference} : sa ligne de trésorerie source a disparu"
    end

    report("verify_allocations", ecarts, "#{CashEntry.count} ligne(s) vérifiée(s)")
  end

  desc "Vérifie les suggestions d'affectation — exit 1 si écart"
  task verify_suggestions: :environment do
    ecarts = []

    AllocationSuggestion.includes(:cash_entry, :allocation_rule).find_each do |suggestion|
      entry = suggestion.cash_entry

      if suggestion.status == "accepted" && entry.cash_allocations.empty?
        ecarts << "Suggestion ##{suggestion.id} : acceptée mais la ligne n'a aucune affectation"
      end

      if suggestion.status == "pending" && entry.posted?
        ecarts << "Suggestion ##{suggestion.id} : encore proposée sur une ligne déjà comptabilisée"
      end
    end

    AllocationRule.find_each do |rule|
      next if AllocationRule::CRITERIA.any? { |c| rule.public_send(c).present? }

      ecarts << "Règle ##{rule.id} « #{rule.label} » : aucun critère, elle s'appliquerait à tout"
    end

    report("verify_suggestions", ecarts, "#{AllocationSuggestion.count} suggestion(s) vérifiée(s)")
  end

  desc "Vérifie les ventilations de séjour — exit 1 si une somme ne colle pas"
  task verify_stay_ventilations: :environment do
    ecarts = []

    CashEntry.joins(:cash_allocations)
             .where(cash_allocations: { document_type: "Stay" })
             .distinct.find_each do |entry|
      affecte = entry.cash_allocations.where(document_type: "Stay").sum(:amount_cents)
      next if affecte == entry.amount_cents

      ecarts << "Ligne ##{entry.id} (#{entry.label}) : ventilation de séjour à #{affecte} " \
                "pour un mouvement de #{entry.amount_cents}"
    end

    report("verify_stay_ventilations", ecarts, "ventilations de séjour vérifiées")
  end

  desc "Vérifie les versements Stripe — exit 1 si un versement ne se referme pas"
  task verify_stripe_payouts: :environment do
    ecarts = []

    StripePayout.includes(:stripe_balance_transactions).find_each do |payout|
      next if payout.stripe_balance_transactions.empty?
      next if payout.balanced?

      ecarts << "Versement #{payout.stripe_id} : transactions à #{payout.transactions_net_cents} " \
                "pour un net de #{payout.amount_cents}"
    end

    report("verify_stripe_payouts", ecarts, "#{StripePayout.count} versement(s) vérifié(s)")
  end

  desc "Vérifie les partages de revenus — exit 1 si une nuitée est relevée deux fois ou une part fausse"
  task verify_revenue_shares: :environment do
    ecarts = []

    # Une nuitée relevée deux fois, c'est un reversement payé deux fois. La
    # régularisation est le SEUL doublon légitime : elle porte une différence,
    # pas un second relevé de la même somme.
    RevenueShareStatementLine.bookings.group(:booking_id).having("COUNT(*) > 1").count.each do |booking_id, count|
      ecarts << "Réservation ##{booking_id} relevée #{count} fois sans régularisation"
    end

    RevenueShareStatement.where.not(status: "draft").includes(:revenue_share_agreement).find_each do |statement|
      if JournalEntry.find_by(source: statement, journal: "purchases").blank?
        ecarts << "Relevé ##{statement.id} (#{statement.period_label}) émis sans écriture"
      end

      attendu = statement.revenue_share_agreement.share_of(statement.base_cents)
      next if statement.share_cents == attendu

      ecarts << "Relevé ##{statement.id} : part de #{statement.share_cents} cents " \
                "pour une base de #{statement.base_cents} à #{statement.revenue_share_agreement.share_percent} % " \
                "(attendu #{attendu})"
    end

    report("verify_revenue_shares", ecarts,
           "#{RevenueShareStatement.count} relevé(s) de partage vérifié(s)")
  end

  desc "Vérifie les comptages de caisse — exit 1 si écart"
  task verify_cash_counts: :environment do
    ecarts = []

    CashCount.validated.includes(:adjustment_cash_entry).find_each do |count|
      date = count.counted_on

      if count.difference_cents.nonzero? && count.comment.blank?
        ecarts << "Comptage du #{date} : écart de #{count.difference_cents} cents sans commentaire"
      end

      if count.resolution == "unexplained" && count.adjustment_cash_entry.blank?
        ecarts << "Comptage du #{date} : écart inexpliqué sans écriture d'ajustement"
      end

      if count.difference_cents.nonzero? && count.resolution.blank?
        ecarts << "Comptage du #{date} : validé avec un écart mais sans suite donnée"
      end

      # `expected_cents` est figé (décision 3). PaperTrail est la seule trace qui
      # permette de le vérifier : si une version postérieure à la validation l'a
      # touché, l'écart raconté par ce comptage n'est plus celui qu'on a constaté.
      reecrit = count.versions.any? do |version|
        version.event == "update" && count.validated_at.present? &&
          version.created_at > count.validated_at && version.changeset.key?("expected_cents")
      end
      ecarts << "Comptage du #{date} : son solde théorique a été réécrit après validation" if reecrit

      entry = count.adjustment_cash_entry
      next if entry.blank?

      if entry.amount_cents != count.difference_cents
        ecarts << "Comptage du #{date} : l'ajustement porte #{entry.amount_cents} cents " \
                  "pour un écart de #{count.difference_cents}"
      end

      ecarts << "Comptage du #{date} : l'ajustement n'est pas comptabilisé" unless entry.posted?
    end

    report("verify_cash_counts", ecarts, "#{CashCount.validated.count} comptage(s) validé(s) vérifié(s)")
  end

  desc "Vérifie les factures d'achat — exit 1 si écart"
  task verify_purchase_invoices: :environment do
    ecarts = []

    PurchaseInvoice.includes(:purchase_invoice_lines, :third_party, :cash_allocations).find_each do |invoice|
      etiquette = "Facture ##{invoice.id} (#{invoice.third_party&.name})"
      lignes = invoice.purchase_invoice_lines.sum(&:amount_cents)

      if %w[to_pay paid].include?(invoice.status)
        ecarts << "#{etiquette} : #{invoice.status_label.downcase} sans écriture d'achat" if invoice.posted_at.blank?

        if JournalEntry.unscoped.find_by(source: invoice, journal: "purchases").blank?
          ecarts << "#{etiquette} : aucune écriture au journal des achats ne la référence"
        end
      end

      if invoice.status != "to_process" && lignes != invoice.total_cents
        ecarts << "#{etiquette} : lignes à #{lignes} cents pour un total de #{invoice.total_cents}"
      end

      next unless invoice.paid?

      couvert = invoice.cash_allocations.sum(:amount_cents).abs
      next if couvert >= invoice.total_cents

      ecarts << "#{etiquette} : marquée payée alors que #{couvert} cents seulement sont rapprochés " \
                "sur #{invoice.total_cents}"
    end

    report("verify_purchase_invoices", ecarts, "#{PurchaseInvoice.count} facture(s) d'achat vérifiée(s)")
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
