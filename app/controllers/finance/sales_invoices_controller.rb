module Finance
  # Comptabilité > Ventes (epic #240, phase 6).
  #
  # Le registre des factures émises dans OkiOki. Claudy ne les produit pas — il
  # les garde, les relie à ce qu'elles facturent, et dit lesquelles sont payées.
  # Jusqu'ici la seule trace d'une facture envoyée était une case « envoyée »
  # sur un séjour : ni numéro, ni PDF, ni montant, ni moyen de savoir si
  # l'argent était arrivé.
  #
  # Depuis le 2026-10-30, toute facture de vente y a sa place : sans
  # réservation, on l'enregistre ici avec son tiers et ses lignes, et son
  # écriture part au journal Ventes (`SalesInvoices::Record`).
  class SalesInvoicesController < Finance::AccountingBaseController
    before_action :get_invoice, only: %i[show edit update destroy]

    breadcrumb "Ventes", :finance_sales_invoices_path, match: :exact

    def index
      @entities = LegalEntity.actives.ordered
      @status = params[:status].presence_in(SalesInvoice::STATUSES)
      @entity = LegalEntity.find_by(id: params[:legal_entity_id])
      @from = parsed_date(params[:from])
      @to = parsed_date(params[:to])
      @query = params[:q].presence
      @kind = params[:type].presence_in(SalesInvoice::KINDS)
      @third_party = ThirdParty.find_by(id: params[:third_party_id])
      @third_parties = ThirdParty.where(id: SalesInvoice.select(:third_party_id)).ordered

      @invoices = filtered.ordered.includes(:customer, :third_party, :legal_entity, :sales_invoice_sources)
      # Les totaux portent sur le FILTRE, contrairement à ceux de la file des
      # achats : ici on vient chercher « combien ai-je facturé en juin », pas une
      # boussole globale. Une note de crédit se déduit du facturé.
      @total_cents = filtered.invoices.sum(:total_cents) - filtered.credit_notes.sum(:total_cents)
      @unpaid_cents = filtered.invoices.issued.includes(:credit_notes).sum(&:remaining_cents)
    end

    def show
      breadcrumb @invoice.label, finance_sales_invoice_path(@invoice), match: :exact
      @sources = @invoice.sales_invoice_sources.includes(:source)
      @allocations = @invoice.cash_allocations.includes(:cash_entry, :general_account, :team).ordered
      @lines = @invoice.sales_invoice_lines.includes(:general_account, :team)
      @credit_notes = @invoice.credit_note? ? [] : @invoice.credit_notes.ordered
    end

    # Depuis la file Facturation, `kind` + `id` désignent ce qu'on facture,
    # avec la même table de correspondance que la file — un `params` fantaisiste
    # lève plutôt que de laisser passer un `constantize` arbitraire. Sans eux,
    # c'est une facture sans réservation : tiers et lignes.
    def new
      return new_open if params[:kind].blank?

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
      return create_open if params[:kind].blank?

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

    # Corriger une facture mal saisie. Le lien vers ce qu'elle facture ne bouge
    # pas — c'est lui qui empêche la double facturation. Un nouveau PDF remplace
    # l'ancien ; sans fichier, l'ancien reste.
    def edit
      breadcrumb @invoice.label, finance_sales_invoice_path(@invoice)
      breadcrumb "Modifier", edit_finance_sales_invoice_path(@invoice), match: :exact
      @entities = LegalEntity.actives.ordered
      return unless @invoice.on_issue?

      load_open_form
      render :edit_open
    end

    # Une facture comptabilisée dont l'écriture change est contre-passée puis
    # repassée (`SalesInvoices::Correct`). Un nouveau PDF remplace l'ancien ;
    # sans fichier, l'ancien reste.
    def update
      attrs = params.require(:sales_invoice)
      attributes = @invoice.on_issue? ? open_invoice_params : on_payment_params(attrs)
      SalesInvoices::Correct.new(sales_invoice: @invoice, attributes: attributes,
                                 document: attrs[:document].presence, whodunnit: current_user&.email).run!

      redirect_to finance_sales_invoice_path(@invoice), notice: "#{@invoice.label} mise à jour."
    rescue ActiveRecord::RecordInvalid, SalesInvoices::Correct::Refused, SalesInvoices::Unpost::Refused,
           Accounting::PostSalesInvoice::NotPostable, Accounting::PostSalesInvoice::MissingAccount,
           Accounting::PostDocument::MissingFiscalYear => e
      @entities = LegalEntity.actives.ordered
      flash.now[:alert] = e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : e.message
      if @invoice.on_issue?
        load_open_form
        render :edit_open, status: :unprocessable_entity
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Une facture retirée du registre a existé, et son numéro OkiOki aussi :
    # comptabilisée, son écriture est contre-passée, jamais effacée.
    def destroy
      SalesInvoices::Withdraw.new(sales_invoice: @invoice, whodunnit: current_user&.email).run!
      redirect_to finance_sales_invoices_path, notice: "#{@invoice.label} retirée du registre."
    rescue SalesInvoices::Withdraw::Refused, SalesInvoices::Unpost::Refused => e
      redirect_to finance_sales_invoice_path(@invoice), alert: e.message
    end

    # Reprise (Michael, 2026-10-30) : les écritures de vente déjà au grand
    # livre (Winbooks, journal Ventes tenu à la main) qui attendent leur
    # facture au registre. Le rattachement n'écrit rien au grand livre
    # (`SalesInvoices::AttachEntry`).
    def attachable
      breadcrumb "Rattacher des écritures", attachable_finance_sales_invoices_path, match: :exact
      load_attachable
    end

    def attach
      entry = JournalEntry.find(params[:journal_entry_id])
      service = SalesInvoices::AttachEntry.new(
        journal_entry: entry,
        attributes: { number: params[:number].to_s.strip, third_party_id: params[:third_party_id] },
        whodunnit: current_user&.email
      )
      service.run!

      redirect_to attachable_finance_sales_invoices_path(attachable_query(entry)),
                  notice: attach_notice(service), status: :see_other
    rescue SalesInvoices::AttachEntry::Refused, ActiveRecord::RecordInvalid => e
      message = e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : e.message
      redirect_to attachable_finance_sales_invoices_path(attachable_query(entry)), alert: message, status: :see_other
    end

    # Tout ce qui se lit sans aide (numéro en tête du libellé, tiers sur le
    # 400000) se rattache d'un coup ; chaque écriture dans sa transaction, un
    # refus n'arrête pas les suivantes.
    def attach_all
      load_attachable
      faits = []
      refus = []
      @previews.select(&:ready?).each do |preview|
        service = SalesInvoices::AttachEntry.new(journal_entry: preview.entry, whodunnit: current_user&.email)
        service.run!
        faits << service
      rescue SalesInvoices::AttachEntry::Refused, ActiveRecord::RecordInvalid => e
        refus << "#{preview.entry.reference} : #{e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : e.message}"
      end

      relies = faits.sum { |service| service.linked_allocations.size }
      notice = "#{faits.size} facture(s) rattachée(s), #{relies} encaissement(s) relié(s)."
      redirect_to attachable_finance_sales_invoices_path(legal_entity_id: @entity.id, year: @year),
                  notice: notice, alert: refus.first(5).join(" · ").presence, status: :see_other
    end

    private

    def load_attachable
      @entities = LegalEntity.actives.ordered
      @entity = @entities.find_by(id: params[:legal_entity_id]) || @entities.first
      @year = params[:year].to_i.between?(2000, 2100) ? params[:year].to_i : Date.current.year
      entries = SalesInvoices::AttachEntry.attachable(legal_entity: @entity, from: Date.new(@year, 1, 1), to: Date.new(@year, 12, 31))
                                          .includes(:fiscal_year, journal_lines: %i[general_account third_party])
      @previews = entries.map { |entry| SalesInvoices::AttachEntry.new(journal_entry: entry).preview }
      @third_parties = ThirdParty.actives.ordered
    end

    def attachable_query(entry)
      { legal_entity_id: entry&.legal_entity_id, year: entry&.entry_date&.year }.compact
    end

    def attach_notice(service)
      invoice = service.invoice
      texte = "#{invoice.label} rattachée à #{invoice.journal_entry.reference}"
      texte += " — #{service.linked_allocations.size} encaissement(s) relié(s)" if service.linked_allocations.any?
      texte += ". #{service.warnings.join(' ')}" if service.warnings.any?
      texte
    end

    def get_invoice = @invoice = SalesInvoice.find(params[:id])

    def new_open
      @invoice = SalesInvoice.new(
        legal_entity: LegalEntity.find_by(id: params[:legal_entity_id]) || default_entity,
        kind: params[:type].presence_in(SalesInvoice::KINDS) || "invoice",
        credited_invoice_id: params[:credited_invoice_id],
        third_party_id: params[:third_party_id],
        issued_on: Date.current,
        posting_mode: "on_issue"
      )
      if (corrigee = @invoice.credited_invoice)
        @invoice.assign_attributes(legal_entity: corrigee.legal_entity, third_party: corrigee.third_party)
      end
      @invoice.sales_invoice_lines.build(vat_rate: @invoice.vat_subject? ? 21 : 0)
      load_open_form
      render :new_open
    end

    def create_open
      attrs = params.require(:sales_invoice)
      service = SalesInvoices::Record.new(attributes: open_invoice_params, document: attrs[:document].presence,
                                          whodunnit: current_user&.email)
      service.run!

      redirect_to finance_sales_invoice_path(service.invoice),
                  notice: "#{service.invoice.label} enregistrée et passée au journal Ventes."
    rescue ActiveRecord::RecordInvalid, Accounting::PostSalesInvoice::NotPostable,
           Accounting::PostSalesInvoice::MissingAccount, Accounting::PostDocument::MissingFiscalYear => e
      @invoice = e.respond_to?(:record) && e.record.is_a?(SalesInvoice) ? e.record : SalesInvoice.new(open_invoice_params)
      @invoice.posting_mode = "on_issue"
      load_open_form
      flash.now[:alert] = e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : e.message
      render :new_open, status: :unprocessable_entity
    end

    def load_open_form
      @entities = LegalEntity.actives.ordered
      @third_parties = ThirdParty.actives.ordered.to_a
      @third_parties |= [@invoice.third_party] if @invoice.third_party
      @revenue_accounts = GeneralAccount.actives.in_class(7).ordered
      @teams = Team.order(:name)
      @creditable = SalesInvoice.invoices.where.not(id: @invoice.id).ordered.includes(:third_party, :customer).limit(300)
    end

    def open_invoice_params
      params.require(:sales_invoice).permit(
        :legal_entity_id, :third_party_id, :kind, :credited_invoice_id, :number, :issued_on, :total, :notes,
        sales_invoice_lines_attributes: %i[id general_account_id team_id analytic_account_id label entered_euros
                                           vat_rate position _destroy]
      ).tap do |permitted|
        permitted[:number] = permitted[:number].to_s.strip if permitted.key?(:number)
        permitted[:total_cents] = cents_from(permitted.delete(:total)) if permitted.key?(:total)
        permitted[:credited_invoice_id] = nil if permitted[:kind] != "credit_note" && permitted.key?(:kind)
        permitted[:notes] = permitted[:notes].presence if permitted.key?(:notes)

        # Le formulaire tape le HTVA et son taux ; la facture en tire la TVA et
        # le TVAC (`SalesInvoice#compute_vat`).
        permitted[:sales_invoice_lines_attributes]&.each_value do |line|
          saisi = line.delete(:entered_euros)
          line[:net_cents] = cents_from(saisi) if saisi.present?
        end
      end.to_h
    end

    def on_payment_params(attrs)
      {
        legal_entity_id: attrs[:legal_entity_id],
        number: attrs[:number].to_s.strip,
        issued_on: attrs[:issued_on],
        total_cents: cents_from(attrs[:total]),
        notes: attrs[:notes].presence
      }
    end

    def filtered
      scope = SalesInvoice.all
      scope = scope.where(status: @status) if @status
      scope = scope.where(legal_entity_id: @entity.id) if @entity
      scope = scope.where(issued_on: @from..) if @from
      scope = scope.where(issued_on: ..@to) if @to
      scope = scope.where("sales_invoices.number ILIKE ?", "%#{@query}%") if @query
      scope = scope.where(kind: @kind) if @kind
      scope = scope.where(third_party_id: @third_party.id) if @third_party
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
