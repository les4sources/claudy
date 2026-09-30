# Aides des specs de la messagerie (phase 1) : un PDF texte minimal, un mail
# brut, un faux serveur IMAP qui note chaque commande, un faux Jev.
module MailIntakeHelpers
  # Un PDF d'une page, valide (table xref calculée), dont `pdf-reader` sait
  # extraire le texte. Une ligne de `lines` = une ligne du PDF.
  # Tout est construit en octets (WinAnsi, comme la police) : un « ° » en UTF-8
  # fausserait les décalages de la table xref.
  def text_pdf(lines)
    stream = +"BT /F1 11 Tf 50 780 Td 14 TL\n".b
    lines.each do |line|
      escaped = line.gsub(/([()\\])/, '\\\\\1').encode("Windows-1252").b
      stream << "(".b << escaped << ") Tj T*\n".b
    end
    stream << "ET".b
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
      "<< /Length #{stream.bytesize} >>\nstream\n".b << stream << "\nendstream".b,
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
    ]
    pdf = +"%PDF-1.4\n".b
    offsets = objects.each_with_index.map do |body, i|
      offset = pdf.bytesize
      pdf << "#{i + 1} 0 obj\n".b << body.b << "\nendobj\n".b
      offset
    end
    xref = pdf.bytesize
    pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n".b
    offsets.each { |o| pdf << format("%010d 00000 n \n", o).b }
    pdf << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n".b
  end

  def raw_mail(message_id:, subject: "Votre facture", from: "Proximus <factures@proximus.be>", pdf: nil,
               body: "Bonjour, veuillez trouver votre facture en annexe.")
    mail = Mail.new
    mail.from = from
    mail.to = "compta@les4sources.be"
    mail.subject = subject
    mail.message_id = message_id
    mail.date = Time.zone.parse("2026-09-12 10:00")
    mail.text_part = Mail::Part.new { body body }
    mail.add_file(filename: "facture.pdf", content: pdf, mime_type: "application/pdf") if pdf
    mail.to_s
  end

  # Un serveur IMAP en mémoire. Il note chaque commande reçue : c'est la
  # preuve que la synchro ne pose aucun flag et ne déplace rien.
  class FakeImap
    FetchData = Struct.new(:attr)

    attr_reader :commands
    attr_accessor :uid_validity

    def initialize(messages, uid_validity: 42)
      @messages = messages # { uid => raw }
      @uid_validity = uid_validity
      @commands = []
    end

    def examine(folder) = @commands << [:examine, folder]

    def status(folder, attrs)
      @commands << [:status, folder, attrs]
      { "UIDVALIDITY" => @uid_validity }
    end

    def uid_search(criteria)
      @commands << [:uid_search, criteria]
      if criteria.first == "UID"
        from = criteria.last.split(":").first.to_i
        found = @messages.keys.select { |uid| uid >= from }
        found.empty? ? [@messages.keys.max].compact : found
      else
        @messages.keys
      end
    end

    def uid_fetch(uids, attrs)
      @commands << [:uid_fetch, uids, attrs]
      uids.map { |uid| FetchData.new({ "UID" => uid, "BODY[]" => @messages[uid], "INTERNALDATE" => Time.current }) }
    end

    def method_missing(name, *args)
      @commands << [name, *args]
    end

    def respond_to_missing?(*) = true
  end

  # Un Jev qui répond ce qu'on lui dit, et garde les questions posées.
  class FakeJev
    attr_reader :calls

    def initialize(configured: true, &responder)
      @configured = configured
      @responder = responder
      @calls = []
    end

    def configured? = @configured

    def ask(state:, questions:)
      @calls << { state: state, questions: questions }
      questions.to_h { |id, question| [id, @responder&.call(id, question) || { "choice" => "aucun", "confidence" => 0.5 }] }
    end
  end
end

RSpec.configure { |config| config.include MailIntakeHelpers }
