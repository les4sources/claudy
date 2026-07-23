module Payments
  class PayService < ServiceBase
    include Routing

    attr_reader :payment
    attr_reader :checkout_session_url

    def initialize(payment_id:)
      @payment = Payment.find(payment_id)
      @report_errors = true
    end

    def run(params = {})
      context = {
        params: params
      }

      catch_error(context: context) do
        run!(params)
      end
    end

    def run!(params = {})
      raise "Ce paiement a déjà été effectué" if @payment.paid?
      @checkout_session_url = stripe_checkout.url
      true
    end

    private

    def stripe_checkout
      StripeService.instance.create_checkout_session(
        client_reference_id: @payment.id,
        success_url: return_url,
        cancel_url: return_url,
        customer_email: prefill_email,
        # Réconciliation comptable : catégorie stable + références métier dans
        # les métadonnées du PaymentIntent (visibles dashboard + exports).
        category: "sejour",
        references: {
          "stay_id"    => @payment.stay&.id,
          "booking_id" => @payment.booking_id,
          "client"     => client_reference_label
        }.compact,
        item: {
          id: @payment.id,
          name: checkout_label,
          description: checkout_description,
          amount: @payment.amount_cents
        }
      )
    end

    # Stay-first (epic #26, Phase 2) : le client revient sur la page séjour dès
    # que le paiement est rattaché à un Stay. Repli sur la page booking pour les
    # paiements historiques, dont les liens circulent encore par email.
    def return_url
      if @payment.stay&.token.present?
        public_stay_url(@payment.stay.token)
      else
        public_booking_url(@payment.booking.token)
      end
    end

    # Libellé lisible par le CLIENT sur la page Stripe — plus de token brut :
    # les dates situent immédiatement le séjour. Repli générique sans dates ;
    # les paiements historiques booking-seuls gardent leur libellé d'origine.
    # « Nom Prénom / Organisation » — pour reconnaître le paiement d'un coup
    # d'œil dans Stripe sans ouvrir Claudy.
    def client_reference_label
      customer = @payment.stay&.customer
      return customer.display_name if customer.respond_to?(:display_name) && customer&.display_name.present?

      [@payment.booking&.firstname, @payment.booking&.lastname].compact_blank.join(" ").presence
    end

    def checkout_label
      stay = @payment.stay
      return "Réservation ##{@payment.booking.token}" if stay&.token.blank?

      if stay.arrival_date.present? && stay.departure_date.present?
        "Séjour aux 4 Sources · du #{I18n.l(stay.arrival_date, format: :long)} " \
          "au #{I18n.l(stay.departure_date, format: :long)}"
      else
        "Séjour aux 4 Sources"
      end
    end

    # Sous-titre Stripe : nature du paiement (acompte / solde / total) puis
    # composition du séjour — de quoi reconnaître SON séjour et comprendre
    # pourquoi le montant demandé diffère du total.
    def checkout_description
      stay = @payment.stay
      return nil unless stay

      [payment_nature(stay), composition_summary(stay)].compact.join(" — ").presence
    end

    # Adossé au TOTAL PRÉVU (`total_amount_cents`) : la notion que le client
    # connaît (devis, email de récap). Acompte tant que rien n'est encaissé,
    # solde ensuite ; rien à préciser si le paiement couvre tout le séjour.
    def payment_nature(stay)
      total = stay.total_amount_cents.to_i
      return nil unless total.positive?

      if @payment.amount_cents >= total
        "Montant total du séjour"
      elsif stay.amount_paid_cents.positive?
        "Solde de #{euros(@payment.amount_cents)} sur un séjour de #{euros(total)}"
      else
        "Acompte de #{euros(@payment.amount_cents)} sur un séjour de #{euros(total)}"
      end
    end

    # Résumé de la composition : hébergement(s) nommé(s), espaces, camping,
    # van, activités actives.
    def composition_summary(stay)
      parts = stay.bookables.filter_map do |bookable|
        case bookable
        when Booking        then bookable.lodging&.name || "Hébergement"
        when SpaceBooking   then "Salles & espaces"
        when CampingBooking then "Camping"
        when VanBooking     then "Emplacement van"
        when HamacBooking   then "Location de hamacs"
        end
      end.uniq
      activities = stay.experience_bookings.active.count
      parts << "#{activities} activité#{"s" if activities > 1}" if activities.positive?
      parts.presence&.join(", ")
    end

    def euros(cents)
      Money.new(cents, "EUR").format
    end

    # Pré-remplit l'email sur la page Stripe (une saisie de moins pour le
    # client). Jamais bloquant : sans email exploitable, Stripe le demandera.
    def prefill_email
      email = @payment.stay&.customer&.email.presence || @payment.booking&.email.presence
      email if email&.match?(URI::MailTo::EMAIL_REGEXP)
    end
  end
end
