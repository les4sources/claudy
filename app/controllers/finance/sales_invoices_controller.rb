module Finance
  # Comptabilité > Ventes (epic #240, phase 6).
  #
  # Le registre des factures émises dans OkiOki. Claudy ne les produit pas — il
  # les garde, les relie à ce qu'elles facturent, et dit lesquelles sont payées.
  # Jusqu'ici la seule trace d'une facture envoyée était une case « envoyée »
  # sur un séjour : ni numéro, ni PDF, ni montant, ni moyen de savoir si
  # l'argent était arrivé.
  class SalesInvoicesController < Finance::AccountingBaseController
    before_action :get_invoice, only: %i[show destroy]

    breadcrumb "Ventes", :finance_sales_invoices_path, match: :exact

    def index
      @entities = LegalEntity.actives.ordered
      @status = params[:status].presence_in(SalesInvoice::STATUSES)
      @entity = LegalEntity.find_by(id: params[:legal_entity_id])
      @from = parsed_date(params[:from])
      @to = parsed_date(params[:to])
      @query = params[:q].presence

      @invoices = filtered.ordered.includes(:customer, :legal_entity, :sales_invoice_sources)
      # Les totaux portent sur le FILTRE, contrairement à ceux de la file des
      # achats : ici on vient chercher « combien ai-je facturé en juin », pas une
      # boussole globale.
      @total_cents = filtered.sum(:total_cents)
      @unpaid_cents = filtered.issued.sum(:total_cents)
    end

    def show
      breadcrumb @invoice.label, finance_sales_invoice_path(@invoice), match: :exact
      @sources = @invoice.sales_invoice_sources.includes(:source)
      @allocations = @invoice.cash_allocations.includes(:cash_entry, :general_account, :team).ordered
    end

    # L'enregistrement part TOUJOURS de la file Facturation : on facture une
    # chose précise, jamais dans le vide. `kind` + `id` désignent cette chose,
    # avec la même table de correspondance que la file — un `params` fantaisiste
    # lève plutôt que de laisser passer un `constantize` arbitraire.
    def new
      @source = find_source
      @invoice = SalesInvoice.new(
        legal_entity: default_entity,
        customer: @source.try(:customer),
        issued_on: Date.current,
        total_cents: source_total_cents(@source)
      )
      @entities = LegalEntity.actives.ordered
      @already_invoiced = SalesInvoiceSource.find_by(source_type: @source.class.name, source_id: @source.id)
    rescue KeyError, ActiveRecord::RecordNotFound
      redirect_to invoicing_path, alert: "Réservation introuvable."
    end

    def create
      @source = find_source
      service = SalesInvoices::Register.new(
        source: @source,
        legal_entity: LegalEntity.find(params[:sales_invoice][:legal_entity_id]),
        number: params[:sales_invoice][:number],
        issued_on: params[:sales_invoice][:issued_on],
        total_cents: cents_from(params[:sales_invoice][:total]),
        notes: params[:sales_invoice][:notes].presence,
        document: params[:sales_invoice][:document],
        whodunnit: current_user&.email
      )
      service.run!

      redirect_to invoicing_path,
                  notice: "Facture #{service.invoice.number} enregistrée — la ligne sort de la file."
    rescue SalesInvoices::Register::AlreadyInvoiced, SalesInvoices::Register::UnknownSource,
           ActiveRecord::RecordInvalid => e
      @invoice = SalesInvoice.new(
        legal_entity_id: params[:sales_invoice][:legal_entity_id],
        number: params[:sales_invoice][:number],
        issued_on: params[:sales_invoice][:issued_on],
        total_cents: cents_from(params[:sales_invoice][:total])
      )
      @entities = LegalEntity.actives.ordered
      @already_invoiced = SalesInvoiceSource.find_by(source_type: @source.class.name, source_id: @source.id)
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_entity
    rescue KeyError, ActiveRecord::RecordNotFound
      redirect_to invoicing_path, alert: "Réservation introuvable."
    end

    # Soft-delete : une facture retirée du registre a existé, et son numéro
    # OkiOki aussi. On la range, on ne la nie pas.
    def destroy
      if @invoice.cash_allocations.any?
        return redirect_to finance_sales_invoice_path(@invoice),
                           alert: "Cette facture porte des affectations bancaires — retire-les d'abord."
      end

      @invoice.destroy
      redirect_to finance_sales_invoices_path, notice: "Facture #{@invoice.number} retirée du registre."
    end

    private

    def get_invoice = @invoice = SalesInvoice.find(params[:id])

    def filtered
      scope = SalesInvoice.all
      scope = scope.where(status: @status) if @status
      scope = scope.where(legal_entity_id: @entity.id) if @entity
      scope = scope.where(issued_on: @from..) if @from
      scope = scope.where(issued_on: ..@to) if @to
      scope = scope.where("sales_invoices.number ILIKE ?", "%#{@query}%") if @query
      scope
    end

    def find_source
      model = Invoicing::Queue.model_for(params[:kind])
      model.find(params[:source_id] || params[:id])
    end

    # Le montant pré-rempli vient de ce qu'on facture : le total du séjour, le
    # prix du réservable. Il reste MODIFIABLE — c'est OkiOki qui fait foi, pas
    # Claudy.
    def source_total_cents(source)
      source.try(:total_amount_cents) || source.try(:price_cents) || 0
    end

    def cents_from(value)
      return 0 if value.blank?

      (value.to_s.tr(",", ".").to_f * 100).round
    end

    def default_entity
      LegalEntity.actives.ordered.first
    end

    def parsed_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
