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
    # `amount_cents` : le montant proposé pour ce séjour (Michael, 2026-10-30).
    # Ce qu'il attend encore des lignes bancaires (son total moins ce qu'elles
    # y ont déjà ventilé) quand c'est moins que ce que la ligne porte : 74 €
    # reçus pour un séjour de 70 € en proposent 70, le reste ira au bar.
    Choice = Struct.new(:stay, :label, :amount_cents, keyword_init: true)

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

      stays.map do |stay|
        Choice.new(stay: stay, label: label(stay, deja[stay.id].to_i), amount_cents: montant(stay, deja[stay.id].to_i))
      end
    end

    # Le séjour que la cascade aurait proposé, présélectionné dans la liste.
    def proposed_stay_id
      MatchStay.new(cash_entry: @entry).run&.stay&.id
    end

    private

    def montant(stay, deja_cents)
      reste_ligne = @entry.remaining_cents
      attendu = stay.total_amount_cents.to_i - deja_cents
      attendu.positive? && attendu < reste_ligne ? attendu : reste_ligne
    end

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
