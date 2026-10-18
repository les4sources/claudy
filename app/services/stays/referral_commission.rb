module Stays
  # Commission due à l'apporteur d'un séjour (Michael, 2026-10-18).
  #
  # RÈGLE : `Stay::REFERRALS[clé][:rate]` × la part HÉBERGEMENT du séjour, et
  # seulement quand le séjour est CONFIRMÉ et ENTIÈREMENT PAYÉ. Pour Semisto :
  # 10 % de l'hébergement.
  #
  # L'ASSIETTE est LUE, jamais recalculée — même règle que les partages de
  # revenus (`RevenueShares::Selection`) : la somme des `bookings.price_cents`
  # des occupations d'hébergement du séjour. C'est le montant « hébergement »
  # que l'app persiste à la création (`PricingModel::Quote#lodging_only_cents`)
  # et celui qu'additionnent les Rapports (`Lodging#revenues`). Les repas,
  # activités, espaces, camping, van, hamacs, draps et le bar vivent sur leurs
  # propres modèles : ils n'y sont donc pas.
  #
  # Une seule chose est extraite à la main : le SUPPLÉMENT CHIEN, que le devis
  # range dans la part hébergement (ligne sans catégorie). Ce n'est pas de
  # l'hébergement ; on le retire au tarif du catalogue, plafonné à l'assiette.
  #
  # TVAC : l'app ne ventile nulle part la TVA d'un séjour — tous les prix du
  # devis, des réservations et des rapports sont TVA comprise. La commission
  # porte donc sur le montant TVAC, celui que le client a payé.
  #
  # Objet de LECTURE pure : il ne crée ni paiement, ni facture, ni relevé.
  class ReferralCommission
    # `paid_cents` : encaissé du séjour, quand l'appelant l'a déjà calculé en
    # lot (index : `Stays::IndexAmounts`). À défaut, lu sur le séjour.
    def initialize(stay, paid_cents: nil)
      @stay = stay
      @paid_cents = paid_cents
    end

    def partner
      Stay::REFERRALS[@stay.referral]
    end

    def applicable?
      partner.present?
    end

    def label = partner&.fetch(:label)
    def rate  = partner&.fetch(:rate)

    # « 10 % »
    def rate_label
      return nil unless rate

      "#{(rate * 100).to_s('F').sub(/\.0+\z/, '')} %"
    end

    # Part hébergement (TVAC), supplément chien retiré.
    def lodging_cents
      [lodging_bookings_cents - dog_supplement_cents, 0].max
    end

    def amount_cents
      applicable? ? (lodging_cents * rate).round : 0
    end

    def confirmed?
      @stay.status == "confirmed"
    end

    # Entièrement payé : quelque chose a été encaissé et rien ne reste dû sur
    # le TOTAL du séjour (même seuil que `Stay#settled?`).
    def fully_paid?
      paid_cents.positive? && paid_cents >= @stay.total_amount_cents.to_i
    end

    # La commission est-elle due ?
    def due?
      applicable? && confirmed? && fully_paid?
    end

    # Pourquoi elle ne l'est pas encore (vide quand elle l'est).
    def pending_reasons
      return [] unless applicable?

      reasons = []
      reasons << "séjour pas encore confirmé" unless confirmed?
      reasons << "séjour pas entièrement payé" unless fully_paid?
      reasons
    end

    private

    def paid_cents
      @paid_cents ||= @stay.amount_paid_cents.to_i
    end

    # Lu sur les `stay_items` (préchargés par l'index et la fiche).
    def lodging_bookings_cents
      @stay.stay_items.map(&:bookable).grep(Booking).sum { |booking| booking.price_cents.to_i }
    end

    def dog_supplement_cents
      return 0 unless @stay.dogs_count.to_i.positive?

      Pricing::Catalog.dog_supplement_cents.to_i
    end
  end
end
