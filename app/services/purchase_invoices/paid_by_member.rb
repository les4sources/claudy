module PurchaseInvoices
  # « Payée par un membre » (Michael, 2026-10-22).
  #
  # La facture AliFar de 24 € est déjà payée : un membre l'a réglée en magasin
  # et se la fera rembourser par sa note de frais. Si la facture passe au
  # journal des achats ET que la note est traitée, la charge compte deux fois.
  #
  # Ici, c'est la NOTE qui porte la charge : la facture devient le justificatif
  # d'une ligne de note (`ExpenseLine#purchase_invoice`) et ne se comptabilise
  # jamais elle-même. Deux façons d'y arriver :
  # - le membre n'a encore rien déclaré : on ajoute la dépense à sa note encore
  #   enregistrée, ou on lui en ouvre une, en reprenant le montant, le compte,
  #   le pôle et la pièce de la facture ;
  # - il l'a déjà déclarée (ticket sur sa note) : on relie cette ligne-là, sans
  #   rien ajouter.
  class PaidByMember < ServiceBase
    class BadStatus < StandardError; end
    class MissingMember < StandardError; end
    class LineNotEligible < StandardError; end

    OPEN_STATUSES = %w[to_process to_validate disputed].freeze

    # Les dépenses déjà déclarées qui peuvent être CETTE facture : même entité,
    # même montant, sur une note de frais qui n'est pas rejetée, et pas encore
    # reliées à une autre facture.
    def self.candidate_lines(invoice)
      ExpenseLine.joins(:expense_report)
                 .where(purchase_invoice_id: nil, amount_cents: invoice.total_cents)
                 .where(expense_reports: { kind: "expenses", legal_entity_id: invoice.legal_entity_id,
                                           status: %w[recorded processing paid], deleted_at: nil })
                 .includes(expense_report: :human)
                 .order(spent_on: :desc, id: :desc)
    end

    # Plus aucune ligne de note ne règle la facture (retirée de la note) : elle
    # revient à la comptabilité, sinon sa charge ne passerait nulle part.
    def self.release_if_unsettled(invoice)
      return if invoice.nil? || !invoice.member_paid?
      return if invoice.expense_lines.exists?

      invoice.update_columns(status: "to_process", updated_at: Time.current)
    end

    def initialize(purchase_invoice:, human: nil, expense_line: nil, user: nil, whodunnit: nil)
      @invoice = purchase_invoice
      @human = human
      @line = expense_line
      @user = user
      @whodunnit = whodunnit || user&.email
    end

    # Rend la note de frais qui rembourse désormais la facture.
    def run!
      check_status!

      PaperTrail.request(whodunnit: @whodunnit || "purchase_invoices") do
        ApplicationRecord.transaction do
          report = @line ? link_existing_line : add_to_member_report
          @invoice.update!(status: "member_paid", dispute_reason: nil)
          report
        end
      end
    end

    # Ce n'était pas un membre, ou pas celui-là : la facture repart « À
    # traiter ». La ligne reste sur la note (elle est peut-être déjà
    # remboursée) ; c'est à la compta de l'en retirer si besoin.
    def undo!
      raise BadStatus, "Cette facture n'est pas payée par un membre." unless @invoice.member_paid?

      reports = @invoice.settling_expense_reports.to_a
      PaperTrail.request(whodunnit: @whodunnit || "purchase_invoices") do
        ApplicationRecord.transaction do
          @invoice.expense_lines.find_each { |line| line.update_columns(purchase_invoice_id: nil, updated_at: Time.current) }
          @invoice.update!(status: "to_process")
        end
      end
      reports
    end

    private

    def check_status!
      return if OPEN_STATUSES.include?(@invoice.status)

      if @invoice.posted?
        raise BadStatus,
              "Cette facture est déjà comptabilisée (#{@invoice.status_label.downcase}) : sa charge est passée, " \
              "la note de frais la compterait une seconde fois."
      end
      raise BadStatus, "Cette facture est déjà #{@invoice.status_label.downcase}."
    end

    def link_existing_line
      unless self.class.candidate_lines(@invoice).exists?(id: @line.id)
        raise LineNotEligible,
              "Cette dépense ne peut pas régler la facture : il faut le même montant " \
              "(#{Money.new(@invoice.total_cents, 'EUR').format}), la même entité, une note de frais non rejetée, " \
              "et une ligne pas encore reliée à une autre facture."
      end

      # `update_columns` : la note est peut-être déjà traitée, et ce lien ne
      # touche ni son montant ni son écriture — seulement ce qu'elle justifie.
      @line.update_columns(purchase_invoice_id: @invoice.id, updated_at: Time.current)
      @line.expense_report
    end

    def add_to_member_report
      raise MissingMember, "Choisis le membre qui a payé la facture." if @human.nil?

      report = open_report || ExpenseReport.create!(
        kind: "expenses", human: @human, legal_entity: @invoice.legal_entity,
        submitted_on: Date.current, created_by: @user
      )
      position = report.expense_lines.maximum(:position).to_i
      expense_lines_from_invoice.each do |attributes|
        position += 1
        line = report.expense_lines.build(attributes.merge(position: position))
        attach_receipt(line)
        line.save!
      end
      report
    end

    # Le membre a déjà une note encore modifiable : la dépense s'y ajoute,
    # comme il l'aurait fait lui-même. Une note par achat ferait des virements
    # de quelques euros.
    def open_report
      ExpenseReport.where(kind: "expenses", human: @human, legal_entity: @invoice.legal_entity, status: "recorded")
                   .recent_first.first
    end

    # Une ligne de note par ligne de facture, avec son compte et son pôle — la
    # compta a déjà fait ce travail sur la facture. Une facture pas encore
    # ventilée donne une seule ligne, sans compte : il s'attribuera au
    # traitement de la note, comme pour toute dépense.
    def expense_lines_from_invoice
      base = { spent_on: @invoice.issued_on, supplier_name: @invoice.third_party.name, doc_kind: "invoice",
               purchase_invoice: @invoice }
      lines = @invoice.purchase_invoice_lines.to_a
      return [base.merge(label: default_label, amount_cents: @invoice.total_cents)] if lines.empty? || !@invoice.balanced?

      lines.map do |line|
        base.merge(label: line.label.presence || default_label, amount_cents: line.amount_cents,
                   general_account: assignable(line.general_account), team: line.team,
                   analytic_account: line.analytic_account)
      end
    end

    def default_label = "Facture #{@invoice.reference.presence || "##{@invoice.id}"}"

    # Une note de frais ne porte que des charges et des immobilisations.
    def assignable(account)
      account if account && ExpenseLine::ACCOUNT_CLASSES.include?(account.klass)
    end

    # La pièce de la facture devient le justificatif de la dépense : le membre
    # n'a pas à redéposer ce que la compta a déjà.
    def attach_receipt(line)
      if @invoice.document.attached?
        line.receipt.attach(@invoice.document.blob)
      else
        line.receipt_on_paper = true
      end
    end
  end
end
