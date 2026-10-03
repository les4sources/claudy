# Les règles d'affectation des carnets de l'épicerie (epic #359, phase 4).
#
# Un virement qui porte le mot-clé imprimé sous le QR d'un carnet se range tout
# seul : `EPICERIE` vers le compte de l'épicerie, `PAIN` vers la boulangerie,
# `ARTISANAT EMILIE` vers l'artisanat. « Se range » au sens des règles : une
# PROPOSITION motivée qu'un humain accepte (`Finance::SuggestAllocations`). Ce
# service ne crée que des règles — aucune allocation, aucune suggestion.
#
# Idempotent : une règle dont la communication porte déjà le mot-clé est gardée
# telle quelle, même si quelqu'un l'a retouchée ou pointée ailleurs. On le
# signale, on n'écrase pas la décision d'un comptable. Un compte de produit
# introuvable non plus ne se crée pas : pas de règle, un avertissement.
#
#   Shop::SeedAllocationRules.new.run                       # les deux carnets + chaque artisan actif
#   Shop::SeedAllocationRules.new.for_consignor(consignor)  # un artisan, à sa création
module Shop
  class SeedAllocationRules
    CONFIDENCE = 90

    Result = Struct.new(:created, :kept, :warnings, keyword_init: true) do
      def to_s
        "#{created.size} règle(s) créée(s), #{kept.size} déjà en place" \
          "#{", #{warnings.size} avertissement(s)" if warnings.any?}"
      end
    end

    def initialize(settings: ShopSetting.current)
      @settings = settings
    end

    def run
      result = new_result
      return result if entity_missing?(result)

      ShopSetting::NOTEBOOK_KEYWORDS.each do |notebook, keyword|
        seed(notebook: notebook, keyword: keyword,
             label: "Carnet #{ShopSetting::NOTEBOOK_LABELS.fetch(notebook)}", result: result)
      end

      consignors = Consignor.actives.ordered.to_a
      warn_shared_keywords(consignors, result)
      consignors.each { |consignor| seed_consignor(consignor, result) }
      result
    end

    def for_consignor(consignor)
      result = new_result
      return result unless consignor.active?
      return result if entity_missing?(result)

      seed_consignor(consignor, result)
      result
    end

    private

    def new_result = Result.new(created: [], kept: [], warnings: [])

    def entity
      @entity ||= LegalEntity.find_by(name: Finance::SeedCashMotifs::DEFAULT_ENTITY) || LegalEntity.ordered.first
    end

    def entity_missing?(result)
      return false if entity

      result.warnings << "Aucune entité juridique — lance d'abord `rake accounting:seed_reference`."
      true
    end

    def seed_consignor(consignor, result)
      if consignor.first_name.blank?
        result.warnings << "#{consignor.name} : pas de prénom, pas de mot-clé — aucune règle."
        return
      end

      seed(notebook: :craft, keyword: consignor.sheet_communication,
           label: "Artisanat — #{consignor.first_name}", result: result)
    end

    def seed(notebook:, keyword:, label:, result:)
      account = @settings.revenue_account(notebook)
      if account.nil?
        result.warnings << "#{label} : aucun compte de produit pour le carnet " \
                           "#{ShopSetting::NOTEBOOK_LABELS.fetch(notebook)} (compte par défaut " \
                           "#{ShopSetting::DEFAULT_ACCOUNT_CODES.fetch(notebook)} introuvable, rien de choisi " \
                           "dans les réglages des carnets) — pas de règle « #{keyword} »."
        return
      end

      existing = existing_rule(keyword)
      if existing
        result.kept << existing
        if existing.general_account_id != account.id
          result.warnings << "La règle « #{existing.label} » reconnaît déjà « #{keyword} » mais propose " \
                             "#{existing.general_account} au lieu de #{account} — laissée telle quelle."
        end
        return
      end

      result.created << AllocationRule.create!(
        label: "#{label} (#{keyword})",
        communication_contains: keyword,
        direction: "incoming",
        confidence: CONFIDENCE,
        general_account: account,
        legal_entity: entity
      )
    end

    # Une règle d'encaissement (ou sans sens) qui cherche déjà ce mot-clé.
    def existing_rule(keyword)
      AllocationRule.where("LOWER(communication_contains) = ?", keyword.downcase)
                    .where(direction: [nil, "", "incoming"])
                    .order(:id).first
    end

    # Deux Émilie produisent le même mot-clé : la règle range bien le virement
    # en artisanat, mais personne ne peut dire de laquelle il s'agit. On le dit.
    def warn_shared_keywords(consignors, result)
      consignors.group_by(&:sheet_communication).each do |keyword, group|
        next if group.size < 2

        result.warnings << "#{group.map(&:name).to_sentence} partagent le mot-clé « #{keyword} » : " \
                           "leurs virements se rattacheront à la main."
      end
    end
  end
end
