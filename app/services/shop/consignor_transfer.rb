# Le virement d'un client pour un artisan (epic #359, phase 4).
#
# Le QR de la feuille d'Émilie pointe sur le compte de la fondation, avec la
# communication `ARTISANAT EMILIE` (décision 16). Quand la ligne bancaire est
# affectée au compte artisanat, il faut savoir À QUI elle revient : c'est ce qui
# alimente « reçu en banque » sur le relevé d'Émilie.
#
# Rien ne se pose tout seul : le mot-clé PRÉ-REMPLIT le choix de l'artisan sur
# l'écran d'affectation, et l'artisan n'est rattaché qu'au moment où un humain
# affecte la ligne (invariant des services `Finance::*`).
#
# Seuls les encaissements BANCAIRES portent un artisan. Les ventes payées en
# espèces sont déclarées ligne par ligne sur le relevé ; rattacher en plus une
# ligne de caisse les compterait deux fois.
module Shop
  class ConsignorTransfer
    attr_reader :cash_entry

    # `consignors:` — la liste des artisans, chargée une fois par la file
    # « À affecter » plutôt qu'une fois par ligne.
    def initialize(cash_entry:, settings: ShopSetting.current, consignors: nil)
      @cash_entry = cash_entry
      @settings = settings
      @consignors = consignors
    end

    def craft_account
      return @craft_account if defined?(@craft_account)

      @craft_account = @settings.revenue_account(:craft)
    end

    # La ligne peut-elle revenir à un artisan ?
    def eligible?
      cash_entry.incoming? && cash_entry.cash_account&.kind != "cash" && craft_account.present?
    end

    # L'affectation demandée va-t-elle au compte artisanat ?
    def craft_allocation?(general_account_id)
      eligible? && general_account_id.present? && general_account_id.to_i == craft_account.id
    end

    # L'artisan que désigne la communication : `ARTISANAT EMILIE`, en mot entier,
    # sans casse ni accents. Un seul candidat ou personne — deux Émilie, c'est à
    # un humain de choisir. Un contrat terminé reste reconnu (un virement peut
    # arriver après), mais un artisan actif l'emporte sur un homonyme parti.
    def suggested_consignor
      text = normalize(cash_entry.communication)
      return nil if text.blank?

      candidates = (@consignors || Consignor.all).select do |consignor|
        consignor.first_name.present? && text.match?(keyword_pattern(consignor.sheet_communication))
      end
      candidates = candidates.select(&:active?) if candidates.size > 1
      candidates.one? ? candidates.first : nil
    end

    # Rattache (ou détache, avec `nil`) l'artisan choisi par l'humain.
    def link!(consignor)
      return unless eligible?

      cash_entry.update!(consignor: consignor)
    end

    # Une affectation au compte artisanat retirée : si plus aucune ne reste, la
    # ligne n'est plus le virement de personne.
    def unlink_if_orphan!
      return if cash_entry.consignor_id.nil?
      return if craft_account && cash_entry.cash_allocations.where(general_account_id: craft_account.id).exists?

      cash_entry.update!(consignor: nil)
    end

    private

    def normalize(value) = I18n.transliterate(value.to_s).upcase.squish

    def keyword_pattern(keyword)
      /(?<![A-Z0-9])#{Regexp.escape(keyword)}(?![A-Z0-9])/
    end
  end
end
