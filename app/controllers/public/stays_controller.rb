module Public
  # Page client du séjour-composite (epic #26, Phase 1). Accessible sans Devise,
  # via le jeton général du séjour — comme la page booking historique, qui reste
  # en place pour les liens déjà envoyés.
  #
  # C'est la page que l'email de confirmation ouvre (Malau, 2026-08-20) : elle
  # est donc la PREMIÈRE chose qu'un client voit une fois son séjour acquis, et
  # la seule qu'il rouvrira d'ici son arrivée. Elle porte pour cela sa propre
  # peau « sous-bois » (layout `public_stay`), la même que le funnel — jusqu'ici
  # le client passait d'un formulaire sable et vert forêt à une fiche grise et
  # indigo, comme s'il changeait de maison en payant.
  class StaysController < Public::BaseController
    layout "public_stay"

    # La page d'un séjour n'est pas un carnet de bord : les autres séjours y sont
    # un rappel, pas une archive. On en montre donc peu, et on compte le reste.
    # Les deux listes sont bornées — un client récurrent (nos groupes réguliers
    # en ont plus de cinquante) ferait sinon dérailler la page sur trois écrans
    # de liens avant d'arriver au « une question ? ».
    UPCOMING_VISIBLE = 4
    PAST_VISIBLE = 3

    def show
      stay = Stay.find_by!(token: params[:token])
      @stay = stay.decorate
      @payments = PaymentDecorator.decorate_collection(stay.payments.order(created_at: :asc))
      @upcoming_stays, @past_stays, @upcoming_stays_extra, @past_stays_extra = sibling_stays(stay)
    rescue ActiveRecord::RecordNotFound
      raise ActionController::RoutingError, "Not Found"
    end

    private

    # Les AUTRES séjours confirmés du même client (Michael, 2026-08-20). Un
    # client fidèle des 4 Sources revient : il doit retrouver ses dates depuis
    # n'importe laquelle de ses pages, sans fouiller sa boîte mail.
    #
    # ANTI-FUITE, la règle qui prime sur tout le reste : rien n'est listé pour un
    # client FOURRE-TOUT (générique ou par OTA). Ces comptes agrègent les
    # dossiers de centaines de personnes sans lien entre elles — y afficher
    # l'historique reviendrait à montrer à un client Airbnb les séjours de tous
    # les autres. Le jeton d'un séjour ne donne accès qu'à CE séjour, jamais à un
    # carnet d'adresses (spec : « anti-fuite fourre-tout »).
    #
    # Seuls les séjours CONFIRMÉS sortent : une demande encore en attente n'est
    # pas une information à afficher comme acquise.
    def sibling_stays(stay)
      customer = stay.customer
      return [[], [], 0, 0] if customer.blank? || customer.catch_all?

      others = customer.stays
                       .where(status: "confirmed")
                       .where.not(id: stay.id)
                       .includes(stay_items: :bookable)
                       .to_a

      today = Date.current
      upcoming, past = others.partition do |s|
        s.departure_date.blank? || s.departure_date >= today
      end

      upcoming = upcoming.sort_by { |s| s.arrival_date || Date.new(9999) }
      past     = past.sort_by { |s| s.departure_date || Date.new(0) }.reverse

      [
        StayDecorator.decorate_collection(upcoming.first(UPCOMING_VISIBLE)),
        StayDecorator.decorate_collection(past.first(PAST_VISIBLE)),
        [upcoming.size - UPCOMING_VISIBLE, 0].max,
        [past.size - PAST_VISIBLE, 0].max
      ]
    end
  end
end
