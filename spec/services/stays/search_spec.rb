require "rails_helper"

# Recherche de l'index Séjours (Michael 2026-07-26) : client (prénom / nom /
# email), nom du groupe, et mot dans la note interne — celle du séjour COMME
# celles des bookables historiques, où vit la majorité du corpus.
RSpec.describe Stays::Search do
  def create_customer(**attrs)
    Customer.create!({ email: "c#{SecureRandom.hex(4)}@example.com",
                       customer_type: "individual", first_name: "Jean", last_name: "Dupont" }.merge(attrs))
  end

  def create_stay(customer, notes: nil)
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: Date.today + 5, departure_date: Date.today + 7, notes: notes)
  end

  def attach_booking(stay, notes:)
    booking = Booking.create!(firstname: "Test", from_date: Date.today + 5,
                              to_date: Date.today + 7, adults: 2, notes: notes)
    StayItem.create!(stay: stay, bookable: booking)
    booking
  end

  subject(:results) { described_class.new(Stay.all, query).call }

  describe "recherche par client" do
    let!(:target) { create_stay(create_customer(first_name: "Amandine", last_name: "Leroy")) }
    let!(:other)  { create_stay(create_customer(first_name: "Bruno", last_name: "Martin")) }

    context "sur le prénom" do
      let(:query) { "amandine" } # insensible à la casse
      it { expect(results).to contain_exactly(target) }
    end

    context "sur le nom" do
      let(:query) { "Leroy" }
      it { expect(results).to contain_exactly(target) }
    end

    context "sur un fragment" do
      let(:query) { "mandi" }
      it { expect(results).to contain_exactly(target) }
    end

    context "sans correspondance" do
      let(:query) { "Zorglub" }
      it { expect(results).to be_empty }
    end
  end

  describe "recherche par email" do
    let!(:target) { create_stay(create_customer(email: "contact@asbl-verte.be")) }
    let!(:other)  { create_stay(create_customer) }
    let(:query) { "asbl-verte" }

    it { expect(results).to contain_exactly(target) }
  end

  # « Nom du groupe » recouvre DEUX réalités : la raison sociale du client
  # (`customers.organization_name`) et le `group_name` saisi sur le réservable —
  # c'est ce dernier qui porte la plupart des noms de groupes historiques.
  describe "recherche par nom du groupe" do
    context "sur la raison sociale du client" do
      let!(:target) do
        create_stay(create_customer(customer_type: "organization", organization_name: "Les Scouts de Namur"))
      end
      let!(:other) { create_stay(create_customer) }
      let(:query) { "scouts" }

      it { expect(results).to contain_exactly(target) }
    end

    context "sur le group_name du réservable" do
      let!(:target) { create_stay(create_customer) }
      let!(:other)  { create_stay(create_customer) }
      let(:query) { "Chorale" }

      before do
        Booking.create!(firstname: "T", from_date: Date.today + 5, to_date: Date.today + 7,
                        adults: 2, group_name: "Chorale de Dinant").tap { |b| StayItem.create!(stay: target, bookable: b) }
        Booking.create!(firstname: "T", from_date: Date.today + 5, to_date: Date.today + 7,
                        adults: 2, group_name: "Autre").tap { |b| StayItem.create!(stay: other, bookable: b) }
      end

      it { expect(results).to contain_exactly(target) }
    end

    context "sur le group_name d'un espace" do
      let!(:target) { create_stay(create_customer) }
      let!(:other)  { create_stay(create_customer) }
      let(:query) { "Fanfare" }

      def space_booking(group)
        SpaceBooking.create!(firstname: "T", from_date: Date.today + 5,
                             to_date: Date.today + 7, group_name: group)
      end

      before do
        StayItem.create!(stay: target, bookable: space_booking("Fanfare communale"))
        StayItem.create!(stay: other, bookable: space_booking("Rien"))
      end

      it { expect(results).to contain_exactly(target) }
    end
  end

  describe "recherche dans la note interne du séjour" do
    let!(:target) { create_stay(create_customer, notes: "Prévoir un lit parapluie pour le bébé") }
    let!(:other)  { create_stay(create_customer, notes: "RAS") }
    let(:query) { "parapluie" }

    it { expect(results).to contain_exactly(target) }
  end

  # Le point qui compte : la majorité des notes privées vivent sur les bookables,
  # pas sur `stays.notes` — une recherche qui les raterait serait inutile.
  describe "recherche dans la note interne d'un bookable" do
    let!(:target) { create_stay(create_customer) }
    let!(:other)  { create_stay(create_customer) }
    let(:query) { "chien" }

    before do
      attach_booking(target, notes: "Vient avec un chien")
      attach_booking(other, notes: "Aucune remarque")
    end

    it { expect(results).to contain_exactly(target) }
  end

  describe "garde-fous" do
    let!(:stays) { [create_stay(create_customer), create_stay(create_customer)] }

    context "requête vide" do
      let(:query) { "" }
      it "ne filtre rien" do
        expect(results).to match_array(stays)
      end
    end

    context "requête d'un seul caractère" do
      let(:query) { "a" }
      it "ne filtre rien (sous la longueur minimale)" do
        expect(results).to match_array(stays)
      end
    end

    context "caractère joker saisi littéralement" do
      let!(:target) { create_stay(create_customer, notes: "Remise de 100% accordée") }
      let(:query) { "100%" }

      it "échappe le % et ne ramène QUE la correspondance littérale" do
        expect(results).to contain_exactly(target)
      end
    end
  end

  describe "composition avec les filtres existants" do
    let!(:past)     { create_stay(create_customer(first_name: "Amandine"), notes: nil) }
    let!(:upcoming) { create_stay(create_customer(first_name: "Amandine"), notes: nil) }
    let(:query) { "Amandine" }

    before { past.update_columns(arrival_date: Date.today - 20, departure_date: Date.today - 18) }

    it "reste chaînable sur un scope de période" do
      expect(described_class.new(Stay.past, query).call).to contain_exactly(past)
      expect(described_class.new(Stay.current_and_future, query).call).to contain_exactly(upcoming)
    end
  end
end
