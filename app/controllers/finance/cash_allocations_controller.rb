module Finance
  # Les affectations d'une ligne de trésorerie. Une allocation ne naît que d'un
  # geste humain : il n'existe aucun compte par défaut, aucune règle qui affecte
  # d'office. C'est le défaut de Winbooks éliminé par le schéma.
  class CashAllocationsController < Finance::BaseController
    before_action :get_entry

    # Le verrou sérialise les affectations concurrentes : deux saisies
    # simultanées liraient sinon le même solde restant et passeraient toutes les
    # deux le contrôle de couverture, créant de l'argent qui n'existe pas.
    def create
      allocation = nil

      @entry.with_lock do
        allocation = @entry.cash_allocations.new(allocation_params)
        allocation.save
      end

      if allocation.persisted?
        maybe_post(allocation)
      else
        redirect_to redirect_target, alert: allocation.errors.full_messages.to_sentence
      end
    end

    def destroy
      allocation = @entry.cash_allocations.find(params[:id])

      if allocation.destroy
        redirect_to redirect_target, notice: "Affectation retirée."
      else
        redirect_to redirect_target, alert: allocation.errors.full_messages.to_sentence
      end
    end

    private

    def get_entry = @entry = CashEntry.find(params[:cash_entry_id])
    def finance_secondary = "accounting"

    # Une ligne entièrement affectée se comptabilise dans la foulée : demander
    # un second clic pour un geste qui n'a plus aucune décision à prendre, c'est
    # la meilleure façon de laisser des lignes affectées mais non passées.
    def maybe_post(allocation)
      unless @entry.reload.fully_allocated?
        return redirect_to redirect_target,
                           notice: "Affectation enregistrée — il reste #{Money.new(@entry.remaining_cents, 'EUR').format} à affecter."
      end

      Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: current_user&.email).run!
      redirect_to redirect_target, notice: "Ligne entièrement affectée et comptabilisée."
    rescue Accounting::PostDocument::MissingFiscalYear => e
      redirect_to redirect_target,
                  alert: "Affectation enregistrée, mais la ligne n'a pas pu être comptabilisée : #{e.message}"
    end

    def redirect_target
      params[:from_unallocated].present? ? finance_unallocated_cash_entries_path : finance_cash_entry_path(@entry)
    end

    def allocation_params
      permitted = params.require(:cash_allocation).permit(:general_account_id, :analytic_account_id, :team_id,
                                                          :legal_entity_id, :label, :amount)
      amount = permitted.delete(:amount)
      permitted[:amount_cents] = Monetize.parse(amount.to_s).cents if amount.present?
      permitted
    end
  end
end
