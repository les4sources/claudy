module Finance
  # Charges récurrentes et génération mensuelle (issue #159).
  #
  # La génération n'est JAMAIS une action de fond. L'ActiveJob de l'app est en
  # adaptateur `async` — un job posé en file disparaît au redémarrage — et sur
  # un sujet aussi social qu'une dette entre voisins, un automatisme silencieux
  # serait de toute façon une mauvaise idée. On prévisualise, on confirme.
  class RecurringChargesController < Finance::BaseController
    before_action :get_charge, only: [:edit, :update, :destroy]

    breadcrumb "Charges récurrentes", :finance_recurring_charges_path, match: :exact

    def index
      @charges = RecurringCharge.ordered.includes(member_account: :household)
      @month = parsed_month
    end

    def new
      @charge = RecurringCharge.new(basis: "flat", applies_to: "account", starts_on: Date.current.beginning_of_month, active: true)
    end

    def create
      @charge = RecurringCharge.new(charge_params)

      if @charge.save
        redirect_to finance_recurring_charges_path, notice: "La charge « #{@charge.label} » a été créée."
      else
        flash.now[:alert] = @charge.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @charge.update(charge_params)
        redirect_to finance_recurring_charges_path, notice: "La charge a été mise à jour."
      else
        flash.now[:alert] = @charge.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @charge.soft_delete!(validate: false)
      redirect_to finance_recurring_charges_path, notice: "La charge « #{@charge.label} » a été retirée."
    end

    # Aperçu : ce qui SERAIT créé, ce qui existe déjà, ce qui est ignoré et
    # pourquoi. Rien n'est écrit.
    def preview
      @month = parsed_month
      @report = Finance::GenerateRecurringCharges.new(month: @month, dry_run: true).run!
    end

    def generate
      @month = parsed_month
      report = Finance::GenerateRecurringCharges.new(month: @month, whodunnit: current_user&.email).run!

      redirect_to finance_recurring_charges_path(month: @month.strftime("%Y-%m")),
                  notice: "#{report.created_count} écriture(s) créée(s) pour #{l(@month, format: '%B %Y')}, " \
                          "#{report.existing.size} déjà présente(s), #{report.skipped.size} ignorée(s)."
    end

    private

    def get_charge
      @charge = RecurringCharge.find(params[:id])
    end

    def parsed_month
      raw = params[:month].presence
      raw ? Date.parse("#{raw}-01") : Date.current.beginning_of_month
    rescue Date::Error
      Date.current.beginning_of_month
    end

    def charge_params
      permitted = params.require(:recurring_charge).permit(
        :member_account_id, :household_member_id, :kind, :label, :flow, :basis,
        :applies_to, :rate_key, :split_rate_key, :split_label, :starts_on, :ends_on, :active
      )

      # Montant saisi en euros. Une saisie vide laisse `amount_cents` nul, ce qui
      # est valide quand une clé de barème est fournie — et refusé sinon par la
      # contrainte, pas par un silence.
      raw = params.dig(:recurring_charge, :amount_euros).to_s.strip.tr(",", ".")
      permitted[:amount_cents] = raw.match?(/\A\d+(\.\d+)?\z/) ? (raw.to_f * 100).round : nil
      # Un périmètre et un compte sont exclusifs : on vide le compte plutôt que
      # de laisser la contrainte de base refuser une saisie compréhensible.
      permitted[:member_account_id] = nil if permitted[:applies_to].present? && permitted[:applies_to] != "account"
      permitted[:rate_key] = permitted[:rate_key].presence
      permitted[:split_rate_key] = permitted[:split_rate_key].presence
      permitted
    end

    def finance_secondary = "recurring_charges"
  end
end
