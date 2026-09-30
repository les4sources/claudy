require "net/imap"

module MailIntake
  # Rapatrie les nouveaux mails d'une boîte (messagerie, phase 1).
  #
  # LECTURE SEULE, et c'est un engagement envers l'équipe : la boîte reste
  # celle des humains, qui la lisent aussi dans Roundcube ou sur leur
  # téléphone. D'où `EXAMINE` (la boîte s'ouvre en lecture seule côté serveur)
  # et `BODY.PEEK[]` (lire un message sans le marquer lu). Aucun flag posé,
  # rien de déplacé, rien de supprimé.
  #
  # Le curseur est le dernier UID lu, valable tant que UIDVALIDITY ne bouge
  # pas. Au tout premier passage, on ne remonte que `FIRST_SYNC_DAYS` jours :
  # l'historique de la boîte n'est pas une file de travail.
  class Sync < ServiceBase
    FIRST_SYNC_DAYS = 90
    BATCH_SIZE = 20
    PORT = 993
    # Un logo en signature n'est pas une pièce : les images ne comptent que
    # jointes pour de vrai, et au-delà de ce poids.
    MIN_IMAGE_BYTES = 20_000

    class MissingPassword < StandardError; end

    attr_reader :created

    def initialize(mail_account:, imap: nil)
      @account = mail_account
      @imap = imap
      @created = []
    end

    def run
      catch_error(context: { mail_account_id: @account.id }) do
        run!
        true
      end
    end

    def run!
      raise MissingPassword, "#{@account.password_env_key} absent de l'ENV — la boîte #{@account.address} n'est pas lue." if @account.password.blank? && @imap.nil?

      imap = @imap || connect
      imap.examine(@account.folder)
      validity = imap.status(@account.folder, ["UIDVALIDITY"])["UIDVALIDITY"]
      reset_cursor(validity) if validity != @account.uid_validity

      uids = new_uids(imap)
      uids.each_slice(BATCH_SIZE) do |batch|
        imap.uid_fetch(batch, ["BODY.PEEK[]", "INTERNALDATE"])&.each { |data| ingest(data) }
        @account.update!(last_uid: batch.max)
      end

      @account.update!(last_synced_at: Time.current, last_error: nil)
      @created
    rescue StandardError => e
      @account.update_columns(last_error: "#{e.class} : #{e.message}".truncate(500), updated_at: Time.current)
      raise
    ensure
      if imap && @imap.nil?
        imap.logout rescue nil
        imap.disconnect rescue nil
      end
    end

    private

    def connect
      imap = Net::IMAP.new(@account.imap_host, port: PORT, ssl: true)
      imap.login(@account.imap_username, @account.password)
      imap
    end

    def reset_cursor(validity)
      @account.update!(uid_validity: validity, last_uid: 0)
    end

    # `UID n:*` renvoie toujours au moins le dernier message, même quand son UID
    # est inférieur à n : le filtre `> last_uid` n'est pas décoratif.
    def new_uids(imap)
      uids = if @account.last_uid.zero?
               imap.uid_search(["SINCE", FIRST_SYNC_DAYS.days.ago.to_date.strftime("%d-%b-%Y")])
             else
               imap.uid_search(["UID", "#{@account.last_uid + 1}:*"])
             end
      uids.map(&:to_i).select { |uid| uid > @account.last_uid }.sort
    end

    def ingest(data)
      raw = data.attr["BODY[]"]
      return if raw.blank?

      mail = ::Mail.new(raw)
      message_id = mail.message_id.presence || "sans-id-#{Digest::SHA256.hexdigest(raw)[0, 32]}"
      return if @account.mail_messages.exists?(message_id: message_id)

      message = @account.mail_messages.new(
        message_id: message_id,
        imap_uid: data.attr["UID"],
        from_address: mail.from&.first,
        from_name: mail[:from]&.display_names&.first,
        subject: decoded_subject(mail),
        received_at: mail.date || data.attr["INTERNALDATE"] || Time.current,
        body_text: body_text(mail)
      )
      message.raw.attach(io: StringIO.new(raw), filename: "message-#{data.attr['UID']}.eml",
                         content_type: "message/rfc822")
      message.save!
      attachments_of(mail).each { |part| store_attachment(message, part) }
      @created << message
    end

    def decoded_subject(mail)
      mail.subject.to_s.truncate(250)
    rescue StandardError
      "(sujet illisible)"
    end

    def body_text(mail)
      text = if mail.text_part
               mail.text_part.decoded
             elsif mail.html_part
               ActionController::Base.helpers.strip_tags(mail.html_part.decoded)
             elsif !mail.multipart?
               mail.mime_type == "text/html" ? ActionController::Base.helpers.strip_tags(mail.decoded) : mail.decoded
             end
      text.to_s.encode("UTF-8", invalid: :replace, undef: :replace).squeeze("\n").strip.truncate(20_000)
    rescue StandardError
      nil
    end

    def attachments_of(mail)
      mail.attachments.select do |part|
        type = part.mime_type.to_s
        if type == "application/pdf" || part.filename.to_s.downcase.end_with?(".pdf")
          true
        elsif type.start_with?("image/")
          !part.inline? && part.body.decoded.bytesize >= MIN_IMAGE_BYTES
        else
          false
        end
      end
    end

    def store_attachment(message, part)
      bytes = part.body.decoded
      type = part.filename.to_s.downcase.end_with?(".pdf") ? "application/pdf" : part.mime_type.to_s
      attachment = message.mail_attachments.new(
        filename: part.filename.presence || "piece-jointe",
        content_type: type,
        sha256: Digest::SHA256.hexdigest(bytes)
      )
      attachment.file.attach(io: StringIO.new(bytes), filename: attachment.filename, content_type: type)
      attachment.save!
    end
  end
end
