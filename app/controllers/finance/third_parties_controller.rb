module Finance
  # Comptabilité > Tiers (epic #240, phase 1). Les 269 tiers de la reprise
  # Winbooks vivaient jusqu'ici sans le moindre écran : on les créait par script
  # et on ne pouvait ni les corriger, ni leur donner l'IBAN qui servira à payer
  # une facture d'achat.
  #
  # On ne SUPPRIME pas un tiers, on le désactive : des lignes d'écriture le
  # portent (`dependent: :restrict_with_error`), et une écriture de 2023 doit
  # rester lisible.
  class ThirdPartiesController < Finance::AccountingBaseController
    before_action :get_third_party, only: %i[edit update deactivate reactivate]

    breadcrumb "Tiers", :finance_third_parties_path, match: :exact

    def index
      scope = ThirdParty.ordered.includes(:human, :customer)
      scope = scope.search(params[:q]) if params[:q].present?
      scope = scope.where(kind: params[:kind]) if ThirdParty::KINDS.include?(params[:kind])
      scope = scope.actives if params[:active] != "all"

      @third_parties = scope
      @counts = ThirdParty.group(:kind).count
    end

    def new
      @third_party = ThirdParty.new(kind: "supplier")
    end

    def create
      @third_party = ThirdParty.new(third_party_params)

      if @third_party.save
        redirect_to finance_third_parties_path, notice: "Tiers « #{@third_party.name} » créé."
      else
        flash.now[:alert] = @third_party.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @third_party.update(third_party_params)
        redirect_to finance_third_parties_path, notice: "Tiers « #{@third_party.name} » mis à jour."
      else
        flash.now[:alert] = @third_party.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def deactivate
      @third_party.update(active: false)
      redirect_to finance_third_parties_path, notice: "Tiers « #{@third_party.name} » désactivé."
    end

    def reactivate
      @third_party.update(active: true)
      redirect_to finance_third_parties_path, notice: "Tiers « #{@third_party.name} » réactivé."
    end

    private

    def get_third_party = @third_party = ThirdParty.find(params[:id])

    # Le CODE ne se saisit pas à la création : il se dérive du nom. Le laisser à
    # la main d'un humain, c'est se retrouver avec deux tiers pour le même
    # fournisseur parce que l'un a écrit `ANTARGAZ` et l'autre `ANTAR`.
    def third_party_params
      permitted = params.require(:third_party).permit(:name, :kind, :iban, :vat_number,
                                                      :email, :notes, :active,
                                                      :human_id, :customer_id)
      permitted[:human_id] = nil if permitted[:human_id].blank?
      permitted[:customer_id] = nil if permitted[:customer_id].blank?
      permitted
    end

    def accounting_secondary = "third_parties"
  end
end
