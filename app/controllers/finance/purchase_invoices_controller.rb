module Finance
  # Comptabilité > Achats (epic #240, phase 2).
  #
  # La file des factures fournisseurs, avec ce qu'elles coûtent et où elles en
  # sont. Jusqu'ici elles vivaient dans une boîte mail : la validation était un
  # blocage implicite, donc invisible, et on découvrait au moment de payer que
  # personne n'avait dit oui.
  class PurchaseInvoicesController < Finance::AccountingBaseController
    before_action :get_invoice, only: %i[show edit update submit dispute reopen]
    before_action :get_form_collections, only: %i[new create edit update]

    breadcrumb "Achats", :finance_purchase_invoices_path, match: :exact

    def index
      @scope = filtered
      @invoices = @scope.ordered.includes(:third_party, :legal_entity, :purchase_invoice_lines)
      # Les totaux par statut portent sur TOUTES les factures, pas sur le filtre :
      # c'est une boussole, et une boussole qui suit le filtre ne sert à rien.
      @totals = PurchaseInvoice::STATUSES.index_with do |status|
        base = PurchaseInvoice.with_status(status)
        { count: base.count, cents: base.sum(:total_cents) }
      end
      @third_parties = ThirdParty.actives.suppliers.ordered
      @entities = LegalEntity.actives.ordered
      @teams = Team.ordered
    end

    def show
      breadcrumb(@invoice.reference.presence || "Facture ##{@invoice.id}",
                 finance_purchase_invoice_path(@invoice), match: :exact)
      @journal_entry = JournalEntry.find_by(source: @invoice, journal: "purchases")
      @versions = @invoice.versions.reorder(created_at: :desc).limit(20)
    end

    def new
      @invoice = PurchaseInvoice.new(legal_entity: default_entity, issued_on: Date.current)
      @invoice.purchase_invoice_lines.build
    end

    def edit
      return redirect_to finance_purchase_invoice_path(@invoice), alert: gel_message if @invoice.frozen_content?

      @invoice.purchase_invoice_lines.build if @invoice.purchase_invoice_lines.empty?
    end

    def create
      @invoice = PurchaseInvoice.new(invoice_params)
      attach_document(@invoice)

      if @invoice.save
        redirect_to finance_purchase_invoice_path(@invoice), notice: "Facture enregistrée."
      else
        @invoice.purchase_invoice_lines.build if @invoice.purchase_invoice_lines.empty?
        flash.now[:alert] = doublon_message(@invoice) || @invoice.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def update
      return redirect_to finance_purchase_invoice_path(@invoice), alert: gel_message if @invoice.frozen_content?

      @invoice.assign_attributes(invoice_params)
      attach_document(@invoice)

      if @invoice.save
        redirect_to finance_purchase_invoice_path(@invoice), notice: "Facture mise à jour."
      else
        flash.now[:alert] = doublon_message(@invoice) || @invoice.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def submit
      invoice = PurchaseInvoices::Advance.new(purchase_invoice: @invoice, whodunnit: current_user&.email).submit!
      redirect_to finance_purchase_invoice_path(invoice), notice: notice_for(invoice)
    rescue PurchaseInvoices::Advance::NotBalanced, PurchaseInvoices::Advance::AlreadyPayable,
           Accounting::PostPurchaseInvoice::NotBalanced,
           Accounting::PostPurchaseInvoice::MissingSupplierAccount,
           Accounting::PostDocument::MissingFiscalYear, ActiveRecord::RecordInvalid => e
      redirect_to finance_purchase_invoice_path(@invoice), alert: e.message
    end

    def dispute
      PurchaseInvoices::Advance.new(purchase_invoice: @invoice, whodunnit: current_user&.email)
                               .dispute!(params[:reason])
      redirect_to finance_purchase_invoice_path(@invoice), notice: "Facture contestée, avec son motif."
    rescue PurchaseInvoices::Advance::MissingReason, PurchaseInvoices::Advance::AlreadyPayable,
           ActiveRecord::RecordInvalid => e
      redirect_to finance_purchase_invoice_path(@invoice), alert: e.message
    end

    def reopen
      PurchaseInvoices::Advance.new(purchase_invoice: @invoice, whodunnit: current_user&.email).reopen!
      redirect_to finance_purchase_invoice_path(@invoice), notice: "Facture remise en traitement."
    rescue PurchaseInvoices::Advance::AlreadyPayable, ActiveRecord::RecordInvalid => e
      redirect_to finance_purchase_invoice_path(@invoice), alert: e.message
    end

    private

    def notice_for(invoice)
      if invoice.to_validate?
        "Facture envoyée en validation — le pôle doit dire oui avant qu'elle soit payable."
      else
        "Facture prête à payer, écriture générée au journal des achats."
      end
    end

    def gel_message
      "Cette facture est déjà comptabilisée — corrige-la par contre-passation."
    end

    def filtered
      scope = PurchaseInvoice.all
      scope = scope.with_status(params[:status]) if params[:status].present?
      scope = scope.where(third_party_id: params[:third_party_id]) if params[:third_party_id].present?
      scope = scope.where(legal_entity_id: params[:legal_entity_id]) if params[:legal_entity_id].present?
      if params[:team_id].present?
        scope = scope.where(id: PurchaseInvoiceLine.where(team_id: params[:team_id]).select(:purchase_invoice_id))
      end
      scope = scope.where(issued_on: from_date..) if from_date
      scope = scope.where(issued_on: ..to_date) if to_date
      scope
    end

    def from_date = parse_date(params[:from])
    def to_date = parse_date(params[:to])

    def parse_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end

    def default_entity
      LegalEntity.actives.ordered.find_by("name ILIKE ?", "%fondation%") || LegalEntity.actives.ordered.first
    end

    def get_invoice
      @invoice = PurchaseInvoice.find(params[:id])
    end

    def get_form_collections
      @third_parties = ThirdParty.actives.suppliers.ordered
      @entities = LegalEntity.actives.ordered
      @teams = Team.ordered
      @general_accounts = GeneralAccount.actives.ordered
    end

    # Le sha256 est calculé À L'ARRIVÉE de la pièce (décision 5) : c'est la seule
    # couche qui rattrape une facture renvoyée sous un autre nom de fichier.
    def attach_document(invoice)
      file = params.dig(:purchase_invoice, :document)
      return if file.blank?

      invoice.document.attach(file)
      invoice.pdf_sha256 = Digest::SHA256.hexdigest(file.tempfile.read)
      file.tempfile.rewind
    end

    def doublon_message(invoice)
      if invoice.errors[:pdf_sha256].any?
        existante = PurchaseInvoice.find_by(pdf_sha256: invoice.pdf_sha256)
        return "Cette pièce a déjà été déposée#{lien(existante)}." if existante
      end

      return unless invoice.errors[:number].any?

      existante = PurchaseInvoice.find_by(third_party_id: invoice.third_party_id, number: invoice.number)
      "Ce numéro existe déjà pour ce tiers#{lien(existante)}." if existante
    end

    def lien(invoice)
      return "" if invoice.blank?

      " — voir #{view_context.link_to("la facture ##{invoice.id}", finance_purchase_invoice_path(invoice), class: 'underline')}"
    end

    def invoice_params
      params.require(:purchase_invoice).permit(
        :legal_entity_id, :third_party_id, :number, :issued_on, :due_on, :total_euros,
        :requires_validation, :validation_team_id, :notes,
        purchase_invoice_lines_attributes: %i[id general_account_id team_id analytic_account_id
                                              amount_euros label position _destroy]
      ).tap do |permitted|
        euros = permitted.delete(:total_euros)
        permitted[:total_cents] = to_cents(euros) if euros.present?

        lines = permitted[:purchase_invoice_lines_attributes]
        next if lines.blank?

        lines.each_value do |line|
          montant = line.delete(:amount_euros)
          line[:amount_cents] = to_cents(montant) if montant.present?
        end
      end
    end

    def to_cents(raw) = (raw.to_s.tr(",", ".").to_f * 100).round

    def accounting_secondary = "purchase_invoices"
  end
end
