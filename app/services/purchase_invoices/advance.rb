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

    def initialize(purchase_invoice:, whodunnit: nil)
      @invoice = purchase_invoice
      @whodunnit = whodunnit
    end

    # « Envoyer au paiement » : la facture quitte le traitement. Si un pôle doit
    # valider et ne l'a pas encore fait, elle s'arrête à `to_validate` — le
    # blocage devient visible au lieu de rester implicite.
    def submit!
      raise AlreadyPayable, "Cette facture est déjà #{@invoice.status_label.downcase}." if @invoice.frozen_content?

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
          end
        end
      end

      @invoice.reload
    end

    def dispute!(reason)
      raise MissingReason, "Dis pourquoi tu contestes cette facture." if reason.blank?
      raise AlreadyPayable, "Cette facture est déjà comptabilisée — contre-passe-la." if @invoice.frozen_content?

      PaperTrail.request(whodunnit: @whodunnit || "purchase_invoices") do
        @invoice.update!(status: "disputed", dispute_reason: reason)
      end

      @invoice.reload
    end

    # Retour au traitement : une facture contestée qu'on a corrigée repart de
    # zéro dans le parcours.
    def reopen!
      raise AlreadyPayable, "Cette facture est déjà comptabilisée — contre-passe-la." if @invoice.frozen_content?

      PaperTrail.request(whodunnit: @whodunnit || "purchase_invoices") do
        @invoice.update!(status: "to_process", dispute_reason: nil)
      end

      @invoice.reload
    end
  end
end
