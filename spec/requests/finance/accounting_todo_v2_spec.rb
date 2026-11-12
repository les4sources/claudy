require "rails_helper"

# Comptabilité, nouvelle interface (Michael, 2026-11-12) : la page des
# comptables s'ouvre sur « À faire ». La situation de chaque structure est
# partie dans la Situation financière.
RSpec.describe "Comptabilité — À faire", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "compta-todo@les4sources.be", password: "password123", new_interface: true, access_roles: %w[administratif]) }

  around { |example| travel_to(Time.zone.local(2026, 10, 30, 10)) { example.run } }
  before { sign_in user }

  def page = Nokogiri::HTML(response.body)

  it "montre les files, les échéances, la caisse et les repères, sans la situation des structures" do
    get finance_accounting_path

    expect(response).to have_http_status(:ok)
    expect(page.at_css("h1").text).to eq("À faire")
    expect(page.at_css("[data-accounting-todo]")).to be_present
    expect(page.at_css("[data-accounting-deadlines]").text).to include("Rien à déclarer")
    expect(page.at_css("[data-cash-count-reminder]").text).to include("jamais comptée")
    expect(page.at_css("[data-overview]")).to be_nil
    expect(page.css("[data-page-guide]").size).to eq(1)
  end

  it "ne propose pas la Situation financière à l'Administratif seul" do
    get finance_accounting_path

    labels = page.css("a").map { |a| a.text.squish }
    expect(labels).to include("Comptabilité")
    expect(labels).not_to include("Situation financière")
  end

  it "laisse l'ancienne page à l'ancienne interface" do
    user.update!(new_interface: false)

    get finance_accounting_path

    expect(page.at_css(".ui-acc")).to be_nil
    expect(response.body).to include("Gérer les exercices")
  end
end
