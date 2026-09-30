module Finance
  # Comptabilité > Achats (epic #240, phase 2).
  #
  # La file des factures fournisseurs, avec ce qu'elles coûtent et où elles en
  # sont. Jusqu'ici elles vivaient dans une boîte mail : la validation était un
  # blocage implicite, donc invisible, et on découvrait au moment de payer que
  # personne n'avait dit oui.
  class PurchaseInvoicesController < Finance::AccountingBaseController
    before_action :get_invoice, only: %i[show edit update submit dispute reopen validate_by_team pay_in_cash]
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
      # Les caisses de l'entité : quand il y en a plusieurs, c'est à l'humain de
      # dire de laquelle l'argent sort — la première venue serait un choix muet.
      @cash_accounts = CashAccount.actives.where(kind: "cash", legal_entity_id: @invoice.legal_entity_id).ordered
      @versions = @invoice.versions.reorder(created_at: :desc).limit(20)
    end

    # Depuis une échéance de paiement de l'échéancier (« Encoder la facture ») :
    # l'entité et l'échéance viennent de l'échéance, et la facture s'y lie à
    # l'enregistrement — c'est ce lien qui la soldera quand elle sera payée.
    def new
      @deadline = linked_deadline
      @invoice = PurchaseInvoice.new(legal_entity: @deadline&.legal_entity || default_entity,
                                     issued_on: Date.current, due_on: @deadline&.due_on)
      @mail_attachment = linked_mail_attachment
      prefill_from_mail(@invoice, @mail_attachment) if @mail_attachment
      @invoice.purchase_invoice_lines.build if @invoice.purchase_invoice_lines.empty?
    end

    def edit
      return redirect_to finance_purchase_invoice_path(@invoice), alert: gel_message if @invoice.frozen_content?

      @invoice.purchase_invoice_lines.build if @invoice.purchase_invoice_lines.empty?
    end

    def create
      @invoice = PurchaseInvoice.new(invoice_params)
      attach_document(@invoice)
      @mail_attachment = linked_mail_attachment
      attach_mail_document(@invoice, @mail_attachment)

      @deadline = linked_deadline
      if @invoice.save
        @deadline&.update(purchase_invoice: @invoice)
        settle_mail_attachment(@mail_attachment, @invoice)
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

    # « Payée en caisse » (epic #240, phase 4) : le fournisseur du marché repart
    # avec ses billets. Ce n'est pas une case à cocher — ça crée une VRAIE sortie
    # de caisse affectée sur le 440000, sinon la caisse est fausse d'autant.
    def pay_in_cash
      PurchaseInvoices::PayInCash.new(purchase_invoice: @invoice, paid_on: params[:paid_on],
                                      cash_account: CashAccount.find_by(id: params[:cash_account_id]),
                                      whodunnit: current_user&.email).run!
      redirect_to finance_purchase_invoice_path(@invoice),
                  notice: "Facture payée en espèces — la sortie de caisse est enregistrée."
    rescue PurchaseInvoices::PayInCash::BadStatus, PurchaseInvoices::PayInCash::NoCashAccount,
           PurchaseInvoices::PayInCash::MonthClosed, PurchaseInvoices::PayInCash::MissingAccount,
           Accounting::PostCashEntry::NotFullyAllocated,
           Accounting::PostDocument::MissingFiscalYear,
           ActiveRecord::RecordInvalid, Date::Error => e
      redirect_to finance_purchase_invoice_path(@invoice), alert: e.message
    end

    # Valider ou contester depuis la fiche admin (phase 3), en miroir du canal
    # jeton. Réservé aux membres du pôle désigné et aux comptes sans membre
    # rattaché (`User#global_admin?`) : une facture que le pôle laisse dormir
    # doit pouvoir être débloquée, mais pas par n'importe qui.
    def validate_by_team
      unless @invoice.validatable_by?(current_user)
        return redirect_to finance_purchase_invoice_path(@invoice),
                           alert: "Seuls les membres du pôle #{@invoice.validation_team&.name} peuvent trancher cette facture."
      end

      service = PurchaseInvoices::Validate.new(purchase_invoice: @invoice, user: current_user)

      if params[:decision] == "reject"
        service.reject!(params[:reason])
        redirect_to finance_purchase_invoice_path(@invoice), notice: "Facture contestée, la comptabilité est prévenue."
      else
        service.approve!
        redirect_to finance_purchase_invoice_path(@invoice),
                    notice: "Facture validée et prête à payer, écriture générée au journal des achats."
      end
    rescue PurchaseInvoices::Validate::NotAwaiting, PurchaseInvoices::Validate::MissingReason,
           PurchaseInvoices::Advance::NotBalanced, PurchaseInvoices::Advance::AlreadyPayable,
           Accounting::PostPurchaseInvoice::NotBalanced,
           Accounting::PostPurchaseInvoice::MissingSupplierAccount,
           Accounting::PostDocument::MissingFiscalYear, ActiveRecord::RecordInvalid => e
      redirect_to finance_purchase_invoice_path(@invoice), alert: e.message
    end

    def submit
      invoice = PurchaseInvoices::Advance.new(purchase_invoice: @invoice, whodunnit: current_user&.email).submit!
      notify_validation_team(invoice)
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

    # L'email de demande de validation part À CE MOMENT-LÀ, pas dans un callback
    # du modèle : c'est le geste d'envoyer au paiement qui sollicite le pôle, et
    # un `after_commit` aurait aussi tiré sur les imports et les corrections.
    def notify_validation_team(invoice)
      return unless invoice.to_validate?

      recipients = invoice.validation_recipients
      if recipients.empty?
        Rails.logger.info("[PurchaseInvoices] aucune adresse dans le pôle ##{invoice.validation_team_id} " \
                          "pour la facture ##{invoice.id}")
        return
      end

      recipients.each do |human|
        PurchaseInvoiceMailer.validation_requested(invoice, human.email).deliver_later
      end
    end

    def notice_for(invoice)
      if invoice.to_validate?
        recipients = invoice.validation_recipients
        return "Facture envoyée en validation — mais le pôle n'a aucune adresse : préviens-le à la main." if recipients.empty?

        "Facture envoyée en validation — #{recipients.size} membre(s) du pôle viennent d'être prévenus."
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

    # Seule une échéance de paiement encore sans facture se lie : sinon un lien
    # rejoué remplacerait en silence la facture déjà rattachée.
    def linked_deadline
      return nil if params[:compliance_deadline_id].blank?

      ComplianceDeadline.payments.find_by(id: params[:compliance_deadline_id], purchase_invoice_id: nil)
    end

    # Depuis « Boite de réception » (messagerie, phase 1) : une pièce pas encore
    # encodée. Une pièce déjà liée ne se relie pas, sinon un lien rejoué
    # créerait une seconde facture pour le même PDF.
    def linked_mail_attachment
      return nil if params[:mail_attachment_id].blank?

      MailAttachment.find_by(id: params[:mail_attachment_id], purchase_invoice_id: nil)
    end

    # La proposition préremplit, elle ne décide pas : l'humain relit tout avant
    # d'enregistrer. Un fournisseur désactivé depuis n'est pas proposé.
    def prefill_from_mail(invoice, attachment)
      supplier_id = attachment.proposed(:third_party_id) || supplier_matching_vat(attachment.proposed(:supplier_vat))
      invoice.third_party_id = supplier_id if supplier_id && ThirdParty.actives.suppliers.exists?(id: supplier_id)
      entity_id = attachment.proposed(:legal_entity_id)
      invoice.legal_entity_id = entity_id if entity_id && LegalEntity.actives.exists?(id: entity_id)
      %i[number total_cents issued_on due_on].each do |field|
        value = attachment.proposed(field)
        invoice.public_send("#{field}=", value) if value.present?
      end
      prefill_vat_lines(invoice, attachment.proposed(:vat_lines))
      invoice.notes = "Payée d'avance selon la facture électronique (UBL)." if attachment.proposed(:fully_prepaid)
      invoice.document.attach(attachment.file.blob)
    end

    # Une facture électronique donne la TVA par taux : une ligne de ventilation
    # par taux, au montant TVAC, dont il ne reste qu'à choisir compte et pôle.
    def prefill_vat_lines(invoice, lines)
      Array(lines).each do |line|
        # Un taux déclaré à 0,00 € (3 PETITS POIDS annonce un 0 % vide) ferait
        # une ligne vide, que la validation refuse.
        next if line["total_cents"].to_i.zero?

        percent = line["percent"].to_f
        label = "TVA #{percent == percent.round ? percent.round : percent.to_s.tr('.', ',')} %"
        invoice.purchase_invoice_lines.build(amount_cents: line["total_cents"], label: label)
      end
    end

    # Un fournisseur créé APRÈS la lecture du mail (depuis une facture sœur,
    # typiquement) se retrouve par la TVA lue dans la pièce.
    def supplier_matching_vat(raw)
      vat = MailIntake::InvoiceCandidates.normalize_vat(raw)
      return nil unless vat

      ThirdParty.actives.suppliers.find { |t| MailIntake::InvoiceCandidates.normalize_vat(t.vat_number) == vat }&.id
    end

    # La pièce du mail devient la pièce justificative, sauf si l'humain en a
    # déposé une autre. Le sha256 est celui calculé à l'arrivée du mail.
    def attach_mail_document(invoice, attachment)
      return if attachment.nil? || params.dig(:purchase_invoice, :document).present?

      invoice.document.attach(attachment.file.blob)
      invoice.pdf_sha256 = attachment.sha256
    end

    def settle_mail_attachment(attachment, invoice)
      return if attachment.nil?

      attachment.update!(purchase_invoice: invoice)
      attachment.mail_message.settle_if_complete!(current_user)
      settle_twin_attachments(invoice)
    end

    # OkiOki envoie deux mails pour une même facture — le PDF, puis l'UBL. Les
    # pièces encore en file qui désignent CETTE facture (même fichier, ou même
    # numéro chez le même fournisseur) sont classées avec elle : une facture
    # encodée ne doit pas en laisser une seconde à encoder.
    def settle_twin_attachments(invoice)
      MailAttachment.where(purchase_invoice_id: nil).joins(:mail_message)
                    .merge(MailMessage.pending).includes(:mail_message).find_each do |twin|
        next unless twin.invoice_like? && twin.existing_invoice == invoice

        twin.update!(purchase_invoice: invoice)
        twin.mail_message.settle_if_complete!(current_user)
      end
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
