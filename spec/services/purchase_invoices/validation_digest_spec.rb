require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le récapitulatif du lundi des factures à valider (Michael, 2026-10-30) : un
# email par membre de pôle, à la place d'un email par facture.
RSpec.describe PurchaseInvoices::ValidationDigest do
  include FinanceBuilders
  include ActiveSupport::Testing::TimeHelpers

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fournisseur) { ThirdParty.create!(name: "Antargaz", kind: "supplier") }
  let!(:technique) { Team.create!(name: "Pôle Technique", kind: "economic") }
  let!(:accueil) { Team.create!(name: "Pôle Accueil", kind: "economic") }
  let!(:martin) { Human.create!(name: "Martin", email: "martin@les4sources.be", status: "active") }
  let!(:lea) { Human.create!(name: "Léa", email: "lea@les4sources.be", status: "active") }

  before do
    TeamMembership.create!(team: technique, human: martin)
    TeamMembership.create!(team: accueil, human: martin)
    TeamMembership.create!(team: accueil, human: lea)
    ActionMailer::Base.deliveries.clear
  end

  def facture(team:, status: "to_validate", cents: 10_000)
    invoice = PurchaseInvoice.create!(legal_entity: entity, third_party: fournisseur, issued_on: Date.new(2026, 10, 1),
                                      total_cents: cents, requires_validation: true, validation_team: team)
    invoice.update_columns(status: status)
    invoice
  end

  def destinataires = ActionMailer::Base.deliveries.map { |m| m.to.first }

  it "envoie un seul email par membre, avec les factures de tous ses pôles" do
    facture(team: technique)
    facture(team: accueil, cents: 2_500)

    expect(described_class.new.run).to eq("2 email(s) envoyé(s) pour 2 facture(s) à valider.")

    expect(destinataires).to match_array(%w[martin@les4sources.be lea@les4sources.be])
    expect(ActionMailer::Base.deliveries.find { |m| m.to == ["martin@les4sources.be"] }.subject)
      .to eq("2 factures à valider — 125 €")
    expect(ActionMailer::Base.deliveries.find { |m| m.to == ["lea@les4sources.be"] }.subject)
      .to eq("1 facture à valider — 25 €")
  end

  it "n'envoie rien quand aucune facture n'attend" do
    facture(team: technique, status: "to_pay")
    facture(team: technique, status: "to_process")

    expect(described_class.new.run).to eq("aucune facture à valider.")
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(Setting[described_class::LAST_SENT_KEY]).to be_blank
  end

  it "ignore les membres sans adresse" do
    lea.update_column(:email, nil)
    facture(team: accueil)

    described_class.new.run

    expect(destinataires).to eq(["martin@les4sources.be"])
  end

  it "ne renvoie pas la même semaine, sauf FORCE" do
    facture(team: technique)

    travel_to(Date.new(2026, 11, 2)) { described_class.new.run } # lundi
    travel_to(Date.new(2026, 11, 4)) do # mercredi, même semaine ISO
      expect(described_class.new.run).to include("déjà envoyé")
      expect { described_class.new(force: true).run }.to change { ActionMailer::Base.deliveries.size }.by(1)
    end
    travel_to(Date.new(2026, 11, 9)) do # lundi suivant
      expect { described_class.new.run }.to change { ActionMailer::Base.deliveries.size }.by(1)
    end
  end
end
