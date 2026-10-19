require "rails_helper"

# Liste « Séjours récents » : un séjour sans réservable (séjour vide, activité
# seule) affichait « — » au lieu du client (Michael, 2026-10-19).
RSpec.describe StayDecorator, "#contact_line" do
  it "retombe sur le client quand le séjour n'a aucun réservable" do
    customer = Customer.create!(first_name: "Camille", last_name: "Dubois", email: "camille@example.com")
    stay = Stay.create!(customer: customer, source: "manual", status: "pending")

    expect(stay.decorate.contact_line).to eq("Camille Dubois")
  end
end
