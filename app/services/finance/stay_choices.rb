module Finance
  # Les séjours qu'on peut rapprocher À LA MAIN d'une ligne entrante, depuis sa
  # fiche (Michael, 2026-10-19). `MatchStay` ne propose qu'un séjour au solde
  # ouvert et s'abstient au moindre ex æquo : c'est juste pour une proposition,
  # mais un humain qui a la réponse sous les yeux restait sans geste.
  #
  # La liste est donc plus large que la cascade : les séjours SOLDÉS en font
  # partie, parce qu'un paiement saisi sur la fiche du séjour le solde sans que
  # la ligne bancaire qui l'a payé soit ventilée. Seuls les annulés en sortent.
  # Ce qu'une ligne bancaire a DÉJÀ ventilé sur chaque séjour est écrit dans le
  # libellé : c'est ce qui évite de compter deux fois la même recette.
  class StayChoices
    Choice = Struct.new(:stay, :label, keyword_init: true)

    def initialize(cash_entry:)
      @entry = cash_entry
    end

    # La fenêtre de `MatchStay` : un virement paie un séjour passé depuis moins
    # d'un an, ou un acompte pour un séjour des six prochains mois.
    def choices
      fenetre = (@entry.entry_date - 1.year)..(@entry.entry_date + 6.months)
      stays = Stay.where(departure_date: fenetre)
                  .where("stays.status IS NULL OR stays.status NOT IN (?)", Stay::CANCELED_STATUSES)
                  .includes(:customer).order(arrival_date: :desc, id: :desc).to_a
      deja = CashAllocation.where(document_type: "Stay", document_id: stays.map(&:id))
                           .group(:document_id).sum(:amount_cents)

      stays.map { |stay| Choice.new(stay: stay, label: label(stay, deja[stay.id].to_i)) }
    end

    # Le séjour que la cascade aurait proposé, présélectionné dans la liste.
    def proposed_stay_id
      MatchStay.new(cash_entry: @entry).run&.stay&.id
    end

    private

    def label(stay, deja_cents)
      morceaux = ["##{stay.id}", stay.customer&.name || "sans client",
                  [stay.arrival_date && I18n.l(stay.arrival_date, format: "%d/%m"),
                   I18n.l(stay.departure_date, format: "%d/%m/%Y")].compact.join(" → "),
                  euros(stay.total_amount_cents.to_i)]
      morceaux << "soldé" if stay.payment_status == "paid"
      morceaux << "déjà rapproché #{euros(deja_cents)}" if deja_cents.positive?
      morceaux.join(" · ")
    end

    def euros(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents / 100.0, locale: :fr)
    end
  end
end
