require "rails_helper"

# Epic #248, phase 2 — la demande mensuelle de déclaration à l'artisan.
RSpec.describe ConsignmentMailer, type: :mailer do
  let(:consignor) do
    Consignor.create!(name: "Eline", email: "eline@example.com", settlement_mode: "invoice",
                      commission_percent: 20)
  end
  let(:report) { ConsignmentReport.create!(consignor: consignor, period_month: Date.new(2026, 9, 1)) }
  let(:mail) { described_class.monthly_request(report) }

  it "part à l'artisan avec le lien à jeton de son relevé" do
    expect(mail.to).to eq(["eline@example.com"])
    expect(mail.body.encoded).to include("/depot-vente/#{report.token}")
  end

  it "envoie une copie cachée à la compta" do
    expect(mail.bcc).to include("compta@les4sources.be")
    expect(mail.cc).to be_blank
  end
end
