module Finance
  # Comptabilité > Boite de réception (messagerie, phase 1).
  #
  # La file des mails arrivés sur `compta@`, avec ce que Jev propose d'en
  # faire. On y vient pour vider la file : chaque mail en sort soit par une
  # facture enregistrée (« Créer la facture »), soit par « Ignorer ». Rien n'en
  # sort tout seul — la proposition de Jev prépare le geste, elle ne le fait pas.
  class MailMessagesController < Finance::AccountingBaseController
    before_action :get_message, only: %i[show ignore restore]

    breadcrumb "Boite de réception", :finance_mail_messages_path, match: :exact

    def index
      @status = MailMessage::STATUSES.include?(params[:status]) ? params[:status] : "pending"
      @messages = MailMessage.where(status: @status).recent_first
                             .includes(:mail_account, mail_attachments: :purchase_invoice).limit(200)
      @counts = MailMessage.group(:status).count
      @accounts = MailAccount.actives.order(:address)
      @third_parties = ThirdParty.where(id: proposed_ids("third_party_id")).index_by(&:id)
    end

    def show
      breadcrumb(@message.subject.presence || "Mail ##{@message.id}", finance_mail_message_path(@message), match: :exact)
      @third_parties = ThirdParty.where(id: @message.mail_attachments.filter_map { |a| a.proposed(:third_party_id) }).index_by(&:id)
      @entities = LegalEntity.all.index_by(&:id)
    end

    def ignore
      @message.ignore!(current_user)
      redirect_to finance_mail_messages_path, notice: "Mail sorti de la file. Il reste consultable dans « Ignorés »."
    end

    def restore
      @message.restore!
      redirect_to finance_mail_message_path(@message), notice: "Mail remis dans la file."
    end

    def sync
      MailIntakeJob.perform_later
      redirect_to finance_mail_messages_path, notice: "Relève lancée : les nouveaux mails arrivent d'ici une minute."
    end

    private

    def get_message
      @message = MailMessage.find(params[:id])
    end

    def proposed_ids(field)
      @messages.flat_map(&:mail_attachments).filter_map { |a| a.proposed(field) }
    end

    def accounting_secondary = "mail_messages"
  end
end
