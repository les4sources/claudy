require "rails_helper"
# == Schema Information
#
# Table name: revenue_share_agreements
#
#  id                         :bigint           not null, primary key
#  active                     :boolean          default(TRUE), not null
#  beneficiary_email          :string
#  beneficiary_iban           :text
#  beneficiary_name           :string           not null
#  deleted_at                 :datetime
#  ends_on                    :date
#  period                     :string           default("quarterly"), not null
#  share_percent              :integer          default(50), not null
#  starts_on                  :date             not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  beneficiary_third_party_id :bigint
#  lodging_id                 :bigint           not null
#
# Indexes
#
#  index_revenue_share_agreements_on_active                      (active)
#  index_revenue_share_agreements_on_beneficiary_third_party_id  (beneficiary_third_party_id)
#  index_revenue_share_agreements_on_deleted_at                  (deleted_at)
#  index_revenue_share_agreements_on_lodging_id                  (lodging_id)
#
# Foreign Keys
#
#  fk_rails_...  (beneficiary_third_party_id => third_parties.id)
#  fk_rails_...  (lodging_id => lodgings.id)
#
require Rails.root.join("spec/support/revenue_share_builders")

# Issue #247 — l'accord de partage. La périodicité est un RÉGLAGE : c'est lui
# qui décide de la période proposée, pas une branche de code.
RSpec.describe RevenueShareAgreement do
  include RevenueShareBuilders

  let(:lodging) { build_tiny_house }

  it "refuse une part hors de 1..100" do
    accord = RevenueShareAgreement.new(lodging: lodging, beneficiary_name: "X",
                                       share_percent: 0, starts_on: Date.new(2026, 1, 1))
    expect(accord).not_to be_valid
    expect(accord.errors[:share_percent]).to be_present
  end

  it "refuse une fin antérieure au début" do
    accord = build_agreement(lodging)
    accord.ends_on = accord.starts_on - 1.day
    expect(accord).not_to be_valid
  end

  it "arrondit la part au cent plutôt que de tronquer" do
    accord = build_agreement(lodging, share_percent: 50)
    expect(accord.share_of(50_100)).to eq(25_050)
    expect(accord.share_of(1_001)).to eq(501)
  end

  it "n'affiche jamais l'IBAN en entier" do
    accord = build_agreement(lodging)
    expect(accord.iban_masked).to eq("•••• 7034")
  end

  describe "les périodes proposées" do
    it "propose le dernier trimestre CLOS, jamais celui en cours" do
      accord = build_agreement(lodging, period: "quarterly")
      from, to = accord.next_period_to_report(today: Date.new(2026, 8, 15))

      expect(from).to eq(Date.new(2026, 1, 1))
      expect(to).to eq(Date.new(2026, 3, 31))
      expect(accord.period_label_for(from)).to eq("T1 2026")
    end

    it "passe au mois clos quand la périodicité est mensuelle" do
      accord = build_agreement(lodging, period: "monthly", starts_on: Date.new(2026, 6, 1))
      from, to = accord.next_period_to_report(today: Date.new(2026, 8, 15))

      expect(from).to eq(Date.new(2026, 6, 1))
      expect(to).to eq(Date.new(2026, 6, 30))
    end

    it "saute une période déjà relevée" do
      accord = build_agreement(lodging, period: "quarterly")
      RevenueShareStatement.create!(revenue_share_agreement: accord,
                                    period_from: Date.new(2026, 1, 1),
                                    period_to: Date.new(2026, 3, 31))

      from, = accord.next_period_to_report(today: Date.new(2026, 8, 15))
      expect(from).to eq(Date.new(2026, 4, 1))
    end
  end
end
