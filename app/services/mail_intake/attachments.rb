module MailIntake
  # Les pièces jointes qu'on garde d'un mail, et comment on les range
  # (messagerie). Partagé par la relève et par la relecture des mails déjà
  # relevés : quand Claudy apprend à garder un nouveau type de pièce (l'UBL,
  # 2026-09-30), les mails anciens le récupèrent depuis leur .eml.
  #
  # Idempotent : une pièce déjà rangée (même empreinte, même mail) ne l'est pas
  # deux fois.
  module Attachments
    # Un logo en signature n'est pas une pièce : les images ne comptent que
    # jointes pour de vrai, et au-delà de ce poids.
    MIN_IMAGE_BYTES = 20_000

    module_function

    def store_all(message, mail)
      mail.attachments.each do |part|
        kind = kind_of(part)
        next unless kind

        bytes = part.body.decoded
        attachment = store(message, filename: part.filename.presence || "piece-jointe", bytes: bytes,
                                    content_type: kind == :ubl ? "application/xml" : content_type_of(part))
        store_embedded_pdf(attachment, bytes) if kind == :ubl && attachment
      end
    end

    # Relit le .eml d'un mail déjà relevé pour y reprendre ce que la relève
    # d'alors ne gardait pas.
    def backfill(message)
      return unless message.raw.attached?

      store_all(message, ::Mail.new(message.raw.download))
    end

    def kind_of(part)
      name = part.filename.to_s.downcase
      type = part.mime_type.to_s
      if type == "application/pdf" || name.end_with?(".pdf")
        :pdf
      elsif type.start_with?("image/")
        :image if !part.inline? && part.body.decoded.bytesize >= MIN_IMAGE_BYTES
      elsif type.end_with?("/xml") || name.end_with?(".xml")
        :ubl if Ubl.ubl?(part.body.decoded)
      end
    end

    def content_type_of(part)
      part.filename.to_s.downcase.end_with?(".pdf") ? "application/pdf" : part.mime_type.to_s
    end

    def store(message, filename:, bytes:, content_type:, embedded_in: nil)
      sha = Digest::SHA256.hexdigest(bytes)
      return message.mail_attachments.find_by(sha256: sha) if message.mail_attachments.exists?(sha256: sha)

      attachment = message.mail_attachments.new(filename: filename, content_type: content_type, sha256: sha,
                                                embedded_in: embedded_in)
      attachment.file.attach(io: StringIO.new(bytes), filename: filename, content_type: content_type)
      attachment.save!
      attachment
    end

    def store_embedded_pdf(ubl_attachment, xml)
      pdf = Ubl.new(xml).embedded_pdf
      return unless pdf

      store(ubl_attachment.mail_message, filename: pdf.filename, bytes: pdf.bytes, content_type: pdf.content_type,
                                         embedded_in: ubl_attachment)
    end
  end
end
