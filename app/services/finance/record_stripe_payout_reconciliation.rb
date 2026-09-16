module Finance
  # Rapprocher une ligne bancaire entrante de son versement Stripe (epic #250,
  # phase 2).
  #
  # Deux chemins, selon le mode du compte Stripe — et c'est tout l'objet de
  # l'epic. En mode **`ledger`**, les recettes et les frais sont DÉJÀ entrés au
  # journal, transaction par transaction, sur le compte Stripe : il ne reste que
  # le virement interne. Une seule allocation sur `580000`, avec le versement en
  # `document`, et les deux moitiés du virement se lettrent.
  #
  # En mode **`per_payout`**, rien n'est encore entré : la ligne bancaire EST la
  # recette. On la ventile avec `VentilateStripePayout` — recettes d'un côté,
  # commissions de l'autre, chacune avec son pôle.
  #
  # Dans les deux cas, c'est un humain qui a cliqué : la proposition n'avait rien
  # écrit (invariant B4).
  class RecordStripePayoutReconciliation < ServiceBase
    class WrongDirection < StandardError; end
    class AlreadyReconciled < StandardError; end
    class AmountMismatch < StandardError; end
    class PerPayoutUnsupported < StandardError; end

    def initialize(stripe_payout:, cash_entry:, whodunnit: nil)
      @payout = stripe_payout
      @entry = cash_entry
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { stripe_payout: @payout&.id }) { reconcile }
    def run! = reconcile

    private

    def reconcile
      raise WrongDirection, "Un versement Stripe arrive sur une ligne ENTRANTE." unless @entry.amount_cents.positive?

      if CashAllocation.where(document: @payout).exists?
        raise AlreadyReconciled, "Ce versement est déjà rapproché d'une ligne de trésorerie."
      end

      unless @payout.amount_cents == @entry.amount_cents
        raise AmountMismatch,
              "Le versement vaut #{Money.new(@payout.amount_cents, 'EUR').format} et la ligne " \
              "#{Money.new(@entry.amount_cents, 'EUR').format} — ce n'est pas le même mouvement."
      end

      PaperTrail.request(whodunnit: @whodunnit || "stripe_payout_reconciliation") do
        ApplicationRecord.transaction do
          @entry.lock!
          @payout.ledger? ? allocate_transfer : allocate_ventilation
          Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run! if @entry.reload.fully_allocated?
        end
      end

      @entry.reload
    end

    # Mode `ledger` : le versement n'est qu'un virement interne. Les recettes
    # sont déjà au journal, sur le compte Stripe.
    def allocate_transfer
      @entry.cash_allocations.create!(
        general_account: transfer_account,
        legal_entity: @entry.cash_account.legal_entity,
        document: @payout,
        amount_cents: @entry.amount_cents,
        label: "Versement Stripe #{@payout.account_label} du #{I18n.l(@payout.arrival_date, format: :short)}"
      )
    end

    # Mode `per_payout` : la ligne bancaire EST la recette, il faudrait donc la
    # ventiler en somme ALGÉBRIQUE (recettes positives moins commissions
    # négatives, pour un total égal au net reçu) — c'est précisément ce que
    # produit `VentilateStripePayout`.
    #
    # BLOQUÉ PAR UN INVARIANT DE `CashAllocation` : `same_direction_as_entry`
    # refuse toute allocation de sens contraire au mouvement, et `within_entry_amount`
    # refuse qu'une allocation dépasse le montant de la ligne. Sur une ligne
    # entrante de 1 269 €, ni la ligne de recette (+1 300 €) ni celle de
    # commission (−31 €) ne passent.
    #
    # Ce garde-fou protège la saisie MANUELLE — une faute de signe y transforme
    # un encaissement en décaissement partiel. Le lever, c'est toucher à une
    # règle qui s'applique à TOUTES les affectations de l'application, sur de
    # l'argent : ça se décide, ça ne se contourne pas dans un service. La
    # question est posée sur l'epic #250.
    #
    # En attendant, rien ne régresse : aucun écran ne ventilait un versement
    # `per_payout` avant cette phase — `VentilateStripePayout` n'avait aucun
    # appelant.
    def allocate_ventilation
      raise PerPayoutUnsupported,
            "Le rapprochement automatique d'un versement en mode « par versement » demande une " \
            "ventilation algébrique (recettes moins commissions), que `CashAllocation` refuse " \
            "aujourd'hui sur une même ligne. Affecte cette ligne à la main, ou passe ce compte " \
            "en mode grand livre."
    end

    def transfer_account
      @transfer_account ||= GeneralAccount.find_by(code: GeneralAccount::INTERNAL_TRANSFER_CODE) ||
                            raise(ActiveRecord::RecordNotFound,
                                  "Le compte de virements internes #{GeneralAccount::INTERNAL_TRANSFER_CODE} " \
                                  "n'existe pas — lance `rake accounting:seed_reference`.")
    end
  end
end
