require "rails_helper"

# Epic #55, Phase 5 — mailer de relance du solde exigible (client).
RSpec.describe StayBalanceReminderMailer, type: :mailer do
  let(:customer) do
    Customer.create!(email: "solde@example.com", first_name: "Léa", customer_type: "individual")
  end
  let(:stay) do
    Stay.create!(customer: customer, status: "pending", total_amount_cents: 15_000,
                 arrival_date: Date.today + 14, departure_date: Date.today + 16)
  end

  subject(:mail) { described_class.reminder(stay) }

  it "adresse la relance au client" do
    expect(mail.to).to eq(["solde@example.com"])
  end

  # « Réservation », jamais « séjour », dans les objets (Michael, 2026-10-04).
  it "parle de réservation dans l'objet" do
    expect(mail.subject).to eq("Il reste un solde à régler pour votre réservation aux 4 Sources")
  end

  it "pointe vers la page séjour à jeton (paiement du solde)" do
    # Le lien de la relance porte le jeton public du séjour → /sejour/:token.
    expect(mail.body.encoded).to include(stay.token)
  end

  # Michael, 2026-10-26 : le lien mène à la page de la réservation, pas
  # directement au paiement — son libellé ne doit pas laisser croire le contraire.
  it "libelle le lien « Ma réservation en détail »" do
    html = mail.html_part.body.decoded
    expect(html).to include("Ma réservation en détail")
    expect(html).not_to include("Régler le solde de ma réservation")
  end

  # Michael, 2026-10-26 : une seule phrase, le montant dedans.
  it "annonce le solde en une phrase et signe au nom de l'équipe" do
    html = mail.html_part.body.decoded
    text = mail.text_part.body.decoded
    amount = Money.new(stay.balance_due_cents, "EUR").format(symbol: "€")

    expect(html).to include("Il reste un solde à régler de <strong>#{amount}</strong>.")
    expect(text).to include("Il reste un solde à régler de #{amount}.")
    [html, text].each do |body|
      expect(body).not_to include("Pour finaliser")
      expect(body).to include("L'équipe des 4 Sources")
      expect(body).not_to include("Malau & Michael")
    end
  end

  it "affiche les dates sans fuite de syntaxe Slim" do
    html = mail.html_part.body.decoded
    expect(html).to include(stay.decorate.date_range)
    expect(html).not_to include(":=")
  end

  context "pour un séjour d'un jour" do
    let(:stay) do
      Stay.create!(customer: customer, status: "pending", total_amount_cents: 15_000,
                   arrival_date: Date.new(2026, 11, 8), departure_date: Date.new(2026, 11, 8))
    end

    it "n'affiche qu'une date, sans flèche" do
      html = mail.html_part.body.decoded
      expect(html).to include("Votre date")
      expect(html).to include("8 novembre 2026")
      expect(html).not_to match(/8 novembre 2026\s*→/)
    end
  end

  it "garde les espaces entre les phrases et autour des liens" do
    text = mail.text_part.body.decoded
    expect(text).to include("simple rappel, rien n'est annulé")
    expect(text).to include("ou écrivez à sejours@les4sources.be")

    html = mail.html_part.body.decoded
    expect(html).to match(/simple rappel,\s+rien/)
    expect(html).to match(/écrivez à <a [^>]*>sejours@les4sources\.be/)
  end

  it "rassure explicitement : aucun blocage ni annulation" do
    expect(mail.html_part.body.decoded).to match(/rien n.est annulé|reste bien confirmée/)
  end

  # Issue #232 — un client peut vivre sans email : la relance se tait plutôt que
  # de lever faute de destinataire.
  context "quand le client n'a pas d'adresse email" do
    let(:customer) { Customer.create!(email: nil, first_name: "Jean", last_name: "Sanmail") }

    it "n'envoie rien et ne lève pas" do
      ActionMailer::Base.deliveries.clear

      expect { mail.deliver_now }.not_to raise_error
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
