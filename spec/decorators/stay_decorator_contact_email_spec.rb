require "rails_helper"

# Adresse email affichée sous le nom du client dans la modale séjour (Michael
# 2026-08-29). L'enjeu du test : ne JAMAIS proposer en mailto l'adresse du
# fourre-tout, qui écrirait aux 4 Sources plutôt qu'au client.
RSpec.describe StayDecorator, "#contact_email" do
  it "rend l'adresse du client sur un séjour rattaché à un vrai client" do
    customer = Customer.create!(email: "elise@example.com", customer_type: "individual")
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed")

    expect(stay.decorate.contact_email).to eq("elise@example.com")
  end

  it "préfère l'adresse de la réservation d'origine sur un séjour fourre-tout" do
    customer = Customer.create!(email: Customer::CATCH_ALL_EMAIL, customer_type: "individual")
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed")
    from = Date.today + 210
    booking = Booking.create!(firstname: "Camp", lastname: "Louveteaux", email: "chef@louveteaux.be",
                              adults: 2, children: 0,
                              from_date: from, to_date: from + 2, status: "confirmed")
    StayItem.create!(stay: stay, bookable: booking)

    expect(stay.decorate.contact_email).to eq("chef@louveteaux.be")
  end

  it "ne rend rien quand le fourre-tout n'a aucun contact d'origine" do
    customer = Customer.create!(email: Customer::CATCH_ALL_EMAIL, customer_type: "individual")
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed")

    expect(stay.decorate.contact_email).to be_blank
  end
end
