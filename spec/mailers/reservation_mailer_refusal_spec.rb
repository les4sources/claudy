require "rails_helper"

# L'email de REFUS (décision Michael du 2026-09-08) — le « non » qui manquait au
# flux. Il n'a qu'un travail : dire non, donner le motif tel que l'équipe l'a
# écrit, et laisser une porte ouverte.
RSpec.describe ReservationMailer, "#request_refused", type: :mailer do
  let(:customer) { Customer.create!(email: "guest@example.com", first_name: "Léa") }

  let(:stay) do
    Stay.create!(customer: customer, source: "reservation", status: "canceled",
                 arrival_date: Date.new(2026, 10, 5), departure_date: Date.new(2026, 10, 9),
                 total_amount_cents: 168_500)
  end

  let(:motif) { "Le gîte est déjà réservé sur ces dates." }

  subject(:mail) { described_class.request_refused(stay, motif) }

  it "adresse le mail au client, avec un objet qui ne laisse pas de doute" do
    expect(mail.to).to eq(["guest@example.com"])
    expect(mail.subject).to match(/n'a pas pu être retenue/i)
  end

  it "reprend les dates et le motif TEL QUEL (html ET texte)" do
    html = mail.html_part.body.decoded.gsub(/\s+/, " ")
    text = mail.text_part.body.decoded

    [html, text].each do |body|
      expect(body).to include("5 octobre 2026")
      expect(body).to include("9 octobre 2026")
      expect(body).to include(motif)
    end
  end

  it "laisse une porte ouverte : l'adresse séjours et le téléphone de Malau" do
    html = mail.html_part.body.decoded.gsub(/\s+/, " ")
    text = mail.text_part.body.decoded

    [html, text].each do |body|
      expect(body).to include("sejours@les4sources.be")
      expect(body).to include("+32 (0)490 46 77 10")
    end
  end

  # Ce mail annonce un refus : il ne doit surtout PAS traîner un lien de
  # paiement ni parler d'acompte.
  it "ne porte ni acompte ni lien de paiement" do
    html = mail.html_part.body.decoded.gsub(/\s+/, " ")
    text = mail.text_part.body.decoded

    [html, text].each do |body|
      expect(body).not_to match(/acompte/i)
      expect(body).not_to include("/payments/")
    end
  end

  it "porte la signature du pôle Accueil (html ET texte)" do
    expect(mail.html_part.body.decoded).to include("Pour le pôle Accueil des 4 Sources")
    expect(mail.text_part.body.decoded).to include("Pour le pôle Accueil des 4 Sources")
  end

  # Bug 2026-07-20, toujours d'actualité : deux lignes `|` Slim consécutives se
  # concatènent SANS espace, et `| = "…"` sort un `= "` littéral dans le corps.
  it "rend une prose propre (pas de mots collés ni de `= \"` littéral)" do
    html = mail.html_part.body.decoded.gsub(/\s+/, " ")

    expect(html).to include("Nous ne pouvons malheureusement pas accueillir votre séjour du 5 octobre 2026 au 9 octobre 2026.")
    expect(html).not_to include('= "')
  end

  context "séjour sans dates (import legacy)" do
    let(:stay) do
      Stay.create!(customer: customer, source: "manual", status: "canceled", total_amount_cents: 0)
    end

    it "se replie sur une formule sans dates plutôt que de lever" do
      expect { mail.text_part }.not_to raise_error
      expect(mail.text_part.body.decoded).to include("votre demande de séjour")
    end
  end

  # Issue #232 — un client peut vivre sans email : le mailer se tait plutôt que
  # de lever faute de destinataire.
  context "client sans adresse email" do
    let(:customer) { Customer.create!(email: nil, first_name: "Jean", last_name: "Sanmail") }

    it "n'envoie rien" do
      ActionMailer::Base.deliveries.clear

      expect { described_class.request_refused(stay, motif).deliver_now }.not_to raise_error

      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
