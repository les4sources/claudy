require "rails_helper"

# Bloc « Vos informations » de la page client (Michael, 2026-10-19). Le séjour
# #1554 (une activité seule, client organisation) affichait « — » : la page ne
# lisait que le réservable, absent sur un tel séjour.
RSpec.describe StayDecorator, "#public_contact" do
  def booking(**attrs)
    from = Date.today + 210
    Booking.create!({ adults: 2, children: 0, from_date: from, to_date: from + 2, status: "confirmed" }.merge(attrs))
  end

  it "rend le nom et les coordonnées du client quand le séjour n'a aucun réservable" do
    customer = Customer.create!(customer_type: "organization", organization_name: "Fondation Rurale de Wallonie",
                                email: "contact@frw.be", phone: "+32 81 26 18 82")
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed")

    expect(stay.decorate.public_contact).to eq(
      name: "Fondation Rurale de Wallonie", email: "contact@frw.be", phone: "+3281261882"
    )
  end

  it "ajoute la personne et le groupe de la réservation quand ils disent autre chose" do
    customer = Customer.create!(first_name: "Léa", last_name: "Martin", email: "lea@example.com")
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed")
    StayItem.create!(stay: stay, bookable: booking(firstname: "Léa", lastname: "Martin", group_name: "Chorale"))

    expect(stay.decorate.public_contact[:name]).to eq("Léa Martin · Chorale")
  end

  it "ne répète pas l'email du client en guise de nom" do
    customer = Customer.create!(email: "sans-nom@example.com")
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed")

    contact = stay.decorate.public_contact
    expect(contact[:name]).to eq("—")
    expect(contact[:email]).to eq("sans-nom@example.com")
  end

  it "ne montre jamais le nom ni la boîte d'un client fourre-tout" do
    customer = Customer.find_or_create_by!(email: Customer::CATCH_ALL_EMAIL) { |c| c.first_name = "Client Les 4 Sources" }
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed")
    StayItem.create!(stay: stay, bookable: booking(firstname: "Camp", lastname: "Louveteaux",
                                                   email: "chef@louveteaux.be", phone: "0470 00 00 00"))

    expect(stay.decorate.public_contact).to eq(
      name: "Camp Louveteaux", email: "chef@louveteaux.be", phone: "0470 00 00 00"
    )
  end
end
