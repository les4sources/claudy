require "rails_helper"

# Régression trouvée à la passe navigateur du 2026-08-21 (epic #55).
#
# `card` est le moyen de paiement posé par TOUT paiement en ligne du funnel
# natif — acompte (`Reservations::Builder`) comme solde
# (`Payments::CreateBalanceService`) — et proposé au clavier dans l'admin.
# Le décorateur l'ignorait : la page client affichait, sous « Paiements reçus »,
# une ligne sans montant ni libellé dès qu'un séjour était payé en ligne.
RSpec.describe PaymentDecorator, "moyen de paiement carte" do
  let(:customer) { Customer.create!(email: "carte@example.com", customer_type: "individual") }
  let(:stay) { Stay.create!(customer: customer, status: "confirmed") }

  def decorate(method)
    Payment.create!(stay: stay, amount_cents: 30_000, status: "paid", payment_method: method).decorate
  end

  it "annonce le montant d'un paiement carte, comme pour stripe" do
    expect(decorate("card").line.to_s).to include("300", "en ligne")
  end

  it "lui donne son icône et son libellé" do
    expect(decorate("card").payment_method_emoji.to_s).to include("💳")
    expect(decorate("card").payment_method).to eq("En ligne")
  end

  # Le garde-fou qui manquait : `line` renvoyait un `<p>` VIDE pour un moyen
  # inconnu. Ce paragraphe était « présent », donc le repli sur le montant
  # (`payment.line.presence || payment.amount`) ne se déclenchait jamais.
  it "renvoie nil sur un moyen inconnu, pour laisser jouer le repli sur le montant" do
    expect(decorate("virement_lunaire").line).to be_nil
  end
end
