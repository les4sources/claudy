require "rails_helper"

RSpec.describe MailIntake::Body do
  def html_mail(html, text: nil)
    mail = Mail.new
    mail.from = "Gaëlle <gaelle@example.be>"
    mail.subject = "Re: Paiements"
    mail.html_part = Mail::Part.new do
      content_type "text/html; charset=UTF-8"
      body html
    end
    mail.text_part = Mail::Part.new { body text } if text
    mail
  end

  def plain(html) = Nokogiri::HTML5.fragment(html).text.tr("\u00A0", " ")

  describe ".from_mail (HTML)" do
    let(:apple_reply) do
      <<~HTML
        <html><head><style>p { color: red }</style></head><body>
        <div dir="ltr">Coucou,</div><div dir="ltr">Je viens de régulariser les deux paiements 😇</div>
        <div dir="ltr">Merci du rappel 😉</div><div dir="ltr"><br></div>
        <div dir="ltr">Bisous&nbsp;</div><div dir="ltr">Gaëlle&nbsp;<a href="http://www.lafermeauxchiens.be">www.lafermeauxchiens.be</a></div>
        <div dir="ltr"><br><blockquote type="cite">Le 19 oct. 2026 à 07:49, Compta / Les 4 Sources &lt;compta@les4sources.be&gt; a écrit&nbsp;:<br><br></blockquote></div>
        <blockquote type="cite"><div><p class="MsoNormal">Salut Gaëlle,</p><p class="MsoNormal">&nbsp;</p>
        <p class="MsoNormal">13/03/2026 : Annif 260€ – <a href="javascript:alert(1)">lien</a></p></div></blockquote>
        <img src="https://tracker.example/pixel.gif"><script>alert(1)</script>
        </body></html>
      HTML
    end

    it "garde les lignes, décode les entités et replie la réponse citée" do
      reading = described_class.from_mail(html_mail(apple_reply))

      expect(reading).to be_html
      expect(reading.main).to include("<div dir=\"ltr\">Coucou,</div>").or include("<div>Coucou,</div>")
      expect(plain(reading.main)).to include("Je viens de régulariser").and include("Bisous")
      expect(plain(reading.main)).not_to include("&nbsp;")
      expect(plain(reading.main)).not_to include("a écrit")
      expect(plain(reading.main)).not_to include("Salut Gaëlle")
      expect(plain(reading.quoted)).to include("a écrit").and include("Salut Gaëlle").and include("13/03/2026")
    end

    it "assainit : ni style, ni script, ni image distante, ni lien javascript" do
      reading = described_class.from_mail(html_mail(apple_reply))
      html = reading.main + reading.quoted

      expect(html).not_to match(/<(script|style|img)/)
      expect(html).not_to include("color: red")
      expect(html).not_to include("javascript:")
      expect(html).not_to include("class=")
      expect(reading.main).to include('href="http://www.lafermeauxchiens.be"').and include('target="_blank"')
    end

    it "reconnaît la citation Gmail" do
      html = <<~HTML
        <div dir="ltr">Bonjour,<div><br></div><div>Voici la facture.</div></div><br>
        <div class="gmail_quote"><div dir="ltr" class="gmail_attr">On Mon, Oct 19, 2026 at 9:00 AM Compta &lt;compta@les4sources.be&gt; wrote:<br></div>
        <blockquote class="gmail_quote">Pouvez-vous envoyer la facture ?</blockquote></div>
      HTML
      reading = described_class.from_mail(html_mail(html))

      expect(plain(reading.main)).to include("Voici la facture.")
      expect(plain(reading.main)).not_to include("wrote")
      expect(plain(reading.quoted)).to include("wrote").and include("Pouvez-vous envoyer")
    end

    it "reconnaît l'en-tête Outlook « De : … Envoyé : … »" do
      html = <<~HTML
        <div class="WordSection1"><p class="MsoNormal">Bonjour Michael,</p><p class="MsoNormal">C'est réglé.</p>
        <p class="MsoNormal">&nbsp;</p>
        <div style="border:none;border-top:solid #E1E1E1 1.0pt"><p class="MsoNormal"><b>De&nbsp;:</b> Compta &lt;compta@les4sources.be&gt;<br>
        <b>Envoyé&nbsp;:</b> lundi 19 octobre 2026 07:49<br><b>Objet&nbsp;:</b> Rappel</p></div>
        <p class="MsoNormal">Bonjour, petit rappel.</p></div>
      HTML
      reading = described_class.from_mail(html_mail(html))

      expect(plain(reading.main)).to include("C'est réglé.")
      expect(plain(reading.main)).not_to include("Envoyé")
      expect(plain(reading.quoted)).to include("Envoyé").and include("petit rappel")
      expect(reading.main.gsub(/\s+/, "")).to end_with("réglé.</p></div>")
    end

    it "ne replie rien quand le mail n'est qu'un transfert sans un mot" do
      html = "<div>---------- Forwarded message ---------<br>From: Proximus</div><div>Votre facture est disponible.</div>"
      reading = described_class.from_mail(html_mail(html))

      expect(reading.quoted).to be_nil
      expect(plain(reading.main)).to include("Votre facture est disponible.")
    end

    it "retombe sur la partie texte quand le HTML est vide (image seule)" do
      reading = described_class.from_mail(html_mail('<img src="cid:facture">', text: "Facture en pièce jointe."))

      expect(reading).not_to be_html
      expect(reading.main).to eq("Facture en pièce jointe.")
    end
  end

  describe ".from_mail (texte)" do
    it "replie les lignes citées et leur attribution, même coupée sur deux lignes" do
      mail = Mail.new(body: "Merci, c'est payé.\n\nOn Mon, Oct 19, 2026 at 9:00 AM Compta <compta@les4sources.be>\nwrote:\n> Petit rappel\n> Michael")
      reading = described_class.from_mail(mail)

      expect(reading).not_to be_html
      expect(reading.main).to eq("Merci, c'est payé.")
      expect(reading.quoted).to start_with("On Mon, Oct 19").and include("> Petit rappel")
    end

    it "laisse un mail sans citation entier" do
      reading = described_class.from_mail(Mail.new(body: "Bonjour,\n\nVoici la facture.\n\n\n\nMerci"))

      expect(reading.main).to eq("Bonjour,\n\nVoici la facture.\n\nMerci")
      expect(reading.quoted).to be_nil
    end
  end

  describe ".text_of" do
    it "convertit le HTML en texte : une ligne par bloc, entités décodées" do
      expect(described_class.text_of(html_mail("<div>Un</div>\n<div><br></div>\n<div>Deux</div>"))).to eq("Un\n\nDeux")

      text = described_class.text_of(html_mail("<div>Coucou,</div><div>Bisous&nbsp;Gaëlle &lt;g@x.be&gt;</div><ul><li>Un</li><li>Deux</li></ul>"))

      expect(text).to eq("Coucou,\nBisous Gaëlle <g@x.be>\n• Un\n• Deux")
    end

    it "préfère la partie texte écrite par l'expéditeur" do
      expect(described_class.text_of(html_mail("<p>HTML</p>", text: "Texte"))).to eq("Texte")
    end
  end

  describe ".for" do
    let(:account) { MailAccount.create!(address: "compta@les4sources.be", purpose: "accounting") }

    it "lit le brut gardé sur le mail, même relevé avant cette lecture" do
      message = account.mail_messages.create!(message_id: "x@y", received_at: Time.current,
                                              body_text: "Coucou,Bisous&nbsp;Gaëlle")
      message.raw.attach(io: StringIO.new(html_mail("<div>Coucou,</div><div>Bisous&nbsp;Gaëlle</div>").to_s),
                         filename: "m.eml", content_type: "message/rfc822")

      reading = described_class.for(message)

      expect(reading).to be_html
      expect(plain(reading.main)).to eq("Coucou,Bisous Gaëlle")
      expect(reading.main).to include("<div>Coucou,</div>")
    end

    it "sans brut, décode au moins les entités du texte gardé" do
      message = account.mail_messages.create!(message_id: "z@y", received_at: Time.current,
                                              body_text: "Bisous&nbsp;Gaëlle &lt;g@x.be&gt;")

      expect(described_class.for(message).main).to eq("Bisous Gaëlle <g@x.be>")
    end
  end
end
