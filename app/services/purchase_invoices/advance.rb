module PurchaseInvoices
  # Le passage d'une facture d'achat d'un statut au suivant (epic #240, phase 2).
  #
  # Un seul endroit qui sait dans quel ordre les états s'enchaînent, et ce que
  # chaque passage déclenche. Éparpiller cette logique dans le contrôleur
  # reviendrait à avoir autant de règles que de boutons.
  class Advance < ServiceBase
    class NotBalanced < StandardError; end
    class AlreadyPayable < StandardError; end
    class MissingReason < StandardError; end

    # Ce qui a empêché la sortie de caisse d'une facture déclarée payée en
    # espèces (pas de caisse, mois arrêté…) : la facture reste comptabilisée,
    # « À payer », et le bouton « Payée en caisse » de sa fiche prend le relais.
    attr_reader :settlement_error

    def initialize(purchase_invoice:, whodunnit: nil)
      @invoice = purchase_invoice
      @whodunnit = whodunnit
    end

    # « Envoyer au paiement » : la facture quitte le traitement. Si un pôle doit
    # valider et ne l'a pas encore fait, elle s'arrête à `to_validate` — le
    # blocage devient visible au lieu de rester implicite.
    def submit!
      raise AlreadyPayable, "Cette facture est déjà #{@invoice.status_label.downcase}." if @invoice.frozen_content?
      refuse_member_paid!

      unless @invoice.balanced?
        raise NotBalanced,
              "Il reste #{Money.new(@invoice.total_cents - @invoice.lines_total_cents, 'EUR').format} " \
              "à ventiler avant d'envoyer cette facture au paiement."
      end

      cible = @invoice.next_status

      PaperTrail.request(whodunnit: @whodunnit || "purchase_invoices") do
        ApplicationRecord.transaction do
          @invoice.update!(status: cible, dispute_reason: nil)
          # L'écriture ne naît qu'au passage en « À payer » (décision 3) : une
          # facture qui attend encore l'aval d'un pôle n'est pas une dette.
          if cible == "to_pay"
            Accounting::PostPurchaseInvoice.new(purchase_invoice: @invoice, whodunnit: @whodunnit).run!
            # Une note de crédit liée s'impute tout de suite sur sa facture :
            # l'une peut en sortir « Imputée », l'autre « Payée ».
            RefreshPayment.new(purchase_invoice: @invoice.reload).run! if @invoice.credit_note?
          end
        end
      end

      settle_in_cash if @invoice.to_pay? && @invoice.settled_in_cash?
      @invoice.reload
    end

    def dispute!(reason)
      raise MissingReason, "Dis pourquoi tu contestes cette facture." if reason.blank?
      raise AlreadyPayable, "Cette facture est déjà comptabilisée — contre-passe-la." if @invoice.frozen_content?
      refuse_member_paid!

      PaperTrail.request(whodunnit: @whodunnit || "purchase_invoices") do
        @invoice.update!(status: "disputed", dispute_reason: reason)
      end

      @invoice.reload
    end

    # Retour au traitement : une facture contestée qu'on a corrigée repart de
    # zéro dans le parcours. Une facture payée par un membre se détache de sa
    # note de frais (`PaidByMember#undo!`).
    def reopen!
      raise AlreadyPayable, "Cette facture est déjà comptabilisée — contre-passe-la." if @invoice.frozen_content?
      if @invoice.member_paid?
        PaidByMember.new(purchase_invoice: @invoice, whodunnit: @whodunnit).undo!
        return @invoice.reload
      end

      PaperTrail.request(whodunnit: @whodunnit || "purchase_invoices") do
        @invoice.update!(status: "to_process", dispute_reason: nil)
      end

      @invoice.reload
    end

    private

    # Déclarée payée en espèces à l'encodage (2026-11-12) : les billets sont
    # partis, la sortie de caisse naît maintenant que la dette est au grand
    # livre — avant, elle n'aurait rien à solder. Hors de la transaction de
    # passation : une caisse absente ne doit pas défaire l'écriture d'achat.
    def settle_in_cash
      caisses = CashAccount.actives.where(kind: "cash", legal_entity_id: @invoice.legal_entity_id).count
      if caisses > 1
        # Plusieurs caisses : la première venue serait un choix muet.
        @settlement_error = "#{@invoice.legal_entity.name} a plusieurs caisses : dis de laquelle l'argent est sorti " \
                            "avec « Payée en caisse »."
        return
      end

      PayInCash.new(purchase_invoice: @invoice.reload, paid_on: @invoice.settled_on, whodunnit: @whodunnit).run!
    rescue PayInCash::BadStatus, PayInCash::NoCashAccount, PayInCash::MonthClosed, PayInCash::MissingAccount,
           Accounting::PostCashEntry::NotFullyAllocated, Accounting::PostDocument::MissingFiscalYear,
           ActiveRecord::RecordInvalid => e
      @settlement_error = e.message
    end

    # Payée par un membre, la facture est le justificatif de sa note de frais :
    # l'envoyer au paiement passerait sa charge une seconde fois.
    def refuse_member_paid!
      return unless @invoice.member_paid?

      raise AlreadyPayable,
            "Cette facture est payée par un membre : sa note de frais la rembourse. " \
            "Remets-la d'abord en traitement si ce n'est pas le cas."
    end
  end
end
