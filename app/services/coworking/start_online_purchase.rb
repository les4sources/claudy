module Coworking
  # Achat en ligne d'un pack de coworking depuis le portail client
  # (epic #126, Phase 3).
  #
  # Contrairement à l'achat par l'équipe (Coworking::CreatePack, encaissement
  # hors ligne), le client paie par carte via Stripe Checkout. Le pack naît
  # donc avec un `Payment` en ATTENTE ancré dessus (`coworking_pack_id`) ; c'est
  # le webhook `checkout.session.completed` qui le marquera payé
  # (Stripe::CompletedCheckoutService), et le statut du pack en découle.
  #
  # Le prix vient TOUJOURS du barème (`Pricing::Catalog.coworking_pack_cents`),
  # jamais du formulaire.
  class StartOnlinePurchase < ServiceBase
    attr_reader :pack, :payment, :checkout_url

    def initialize(customer:, days_total:, return_url:)
      @customer = customer
      @days_total = days_total.to_i
      @return_url = return_url
      @report_errors = true
    end

    def run
      unless CoworkingPack::DAYS_OPTIONS.include?(@days_total)
        set_error_message("Ce pack n'existe pas.")
        return false
      end

      catch_error(context: { customer: @customer.id, days: @days_total }) do
        ActiveRecord::Base.transaction do
          @pack = CoworkingPack.create!(
            customer: @customer,
            days_total: @days_total,
            payment_method: "card"
          )
          @payment = Payment.create!(
            coworking_pack: @pack,
            amount_cents: @pack.price_cents,
            payment_method: "card",
            status: "pending"
          )
        end

        @checkout_url = stripe_checkout.url
        @checkout_url.present?
      end
    end

    private

    def stripe_checkout
      StripeService.instance.create_checkout_session(
        client_reference_id: @payment.id,
        success_url: @return_url,
        cancel_url: @return_url,
        customer_email: prefill_email,
        item: {
          id: @payment.id,
          name: "Pack coworking · #{@pack.days_total} journée#{'s' if @pack.days_total > 1}",
          description: "Coworking aux 4 Sources — #{@pack.days_total} journée#{'s' if @pack.days_total > 1}, " \
                       "valable jusqu'au #{I18n.l(@pack.expires_at.to_date, format: :long)}",
          amount: @pack.price_cents
        }
      )
    end

    def prefill_email
      email = @customer.email
      email if email&.match?(URI::MailTo::EMAIL_REGEXP)
    end
  end
end
