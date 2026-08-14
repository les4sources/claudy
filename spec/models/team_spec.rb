# == Schema Information
#
# Table name: teams
#
#  id            :bigint           not null, primary key
#  analytic_code :string
#  deleted_at    :datetime
#  description   :text
#  kind          :string
#  name          :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  parent_id     :bigint
#
# Indexes
#
#  index_teams_on_analytic_code  (analytic_code) UNIQUE
#  index_teams_on_parent_id      (parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (parent_id => teams.id)
#
require 'rails_helper'

# La hiérarchie s'arrête à deux niveaux : une profondeur libre finit toujours
# par produire des agrégats qui dépendent du chemin plutôt que du pôle.
RSpec.describe Team, type: :model do
  let(:economic) { described_class.create!(name: "Pôle économique Accueil", kind: "economic") }

  it "accepte un pôle analytique rattaché à un pôle économique" do
    analytic = described_class.new(name: "Hébergement", kind: "analytic", parent: economic)

    expect(analytic).to be_valid
  end

  it "refuse un troisième niveau" do
    analytic = described_class.create!(name: "Hébergement", kind: "analytic", parent: economic)
    petit_fils = described_class.new(name: "Gîtes", kind: "analytic", parent: analytic)

    expect(petit_fils).not_to be_valid
    expect(petit_fils.errors.full_messages.join).to match(/deux niveaux/i)
  end

  it "refuse un code analytique en double" do
    described_class.create!(name: "Hébergement", kind: "analytic", analytic_code: "HEB")

    expect(described_class.new(name: "Hôtellerie", kind: "analytic", analytic_code: "HEB")).not_to be_valid
  end

  it "laisse un pôle sans classement — c'est le collectif qui tranche, pas le code" do
    expect(described_class.new(name: "Pôle Nature")).to be_valid
  end

  it "distingue ses référents de ses membres" do
    human = Human.create!(name: "Béné")
    autre = Human.create!(name: "Colin")
    TeamMembership.create!(team: economic, human: human, role: "referent")
    TeamMembership.create!(team: economic, human: autre, role: "member")

    expect(economic.referents).to eq([human])
    expect(economic.humans.count).to eq(2)
  end
end
