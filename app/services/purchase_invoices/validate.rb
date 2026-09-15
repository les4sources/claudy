module PurchaseInvoices
  # L'aval du pôle sur une facture d'achat (epic #240, phase 3).
  #
  # Séparé de `PurchaseInvoices::Advance`, qui gouverne le parcours des statuts :
  # ici c'est la RÉPONSE d'une personne qu'on enregistre, et la réponse a deux
  # canaux — le lien de l'email, et la fiche admin. Les deux doivent poser
  # exactement la même trace, sinon « qui a validé » dépend du chemin pris.
  #
  # Valider fait avancer la facture jusqu'au bout : `validated_at` posé, puis
  # `Advance#submit!`, qui la passe `to_pay` et génère l'écriture. C'est voulu —
  # l'aval du pôle EST le dernier verrou avant la dette.
  class Validate < ServiceBase
    class NotAwaiting < StandardError; end
    class MissingReason < StandardError; end
    class Forbidden < StandardError; end

    def initialize(purchase_invoice:, user: nil)
      @invoice = purchase_invoice
      @user = user
    end

    def approve!
      ensure_awaiting!

      PaperTrail.request(whodunnit: whodunnit) do
        @invoice.update!(validated_by: @user, validated_at: Time.current, dispute_reason: nil)
      end

      # `next_status` retombe sur `to_pay` dès que `validated_at` est posé.
      Advance.new(purchase_invoice: @invoice.reload, whodunnit: whodunnit).submit!
    end

    def reject!(reason)
      ensure_awaiting!
      raise MissingReason, "Dis pourquoi cette facture ne va pas." if reason.blank?

      PaperTrail.request(whodunnit: whodunnit) do
        @invoice.update!(status: "disputed", dispute_reason: reason,
                         validated_by: @user, validated_at: nil)
      end

      notify_accounting
      @invoice.reload
    end

    private

    def ensure_awaiting!
      return if @invoice.to_validate?

      raise NotAwaiting, "Cette facture n'attend plus de validation (#{@invoice.status_label.downcase})."
    end

    def whodunnit = @user&.email.presence || "purchase_invoice_validations"

    # La coordination comptable, et elle seule : le fournisseur n'est jamais
    # destinataire d'un de ces emails.
    def notify_accounting
      NotificationSettingsController.accounting_emails.each do |email|
        PurchaseInvoiceMailer.disputed(@invoice, email).deliver_later
      end
    end
  end
end
