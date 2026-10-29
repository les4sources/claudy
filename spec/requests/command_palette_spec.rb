require "rails_helper"

# La palette ⌘K (redesign, Michael 2026-10-29) : un champ pour retrouver un
# séjour, une personne, un écran ou une page du Guide, et lancer les gestes
# fréquents — chaque groupe borné par les droits de la personne.
RSpec.describe "Palette ⌘K", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "palette@les4sources.be", password: "password123", new_interface: true) }
  let!(:claire) { Customer.create!(email: "claire@example.com", first_name: "Claire", last_name: "Dubois") }

  def page = Nokogiri::HTML(response.body)
  def groups = page.css(".ui-cmd-gl").map { |label| label.text.squish }

  it "trouve le séjour, le client et propose un séjour pour lui" do
    stay = Stay.create!(customer: claire, source: "manual", status: "pre_confirmed",
                        arrival_date: Date.current + 3, departure_date: Date.current + 5)
    sign_in user

    get command_search_path(q: "dub")

    expect(response).to have_http_status(:ok)
    expect(groups).to include("Séjours", "Personnes", "Actions")
    séjour = page.at_css(".ui-cmd-i[href='#{stay_path(stay)}']")
    expect(séjour.text.squish).to include("Claire Dubois", "##{stay.id}", "Pré-confirmé")
    expect(séjour.at_css("mark").text).to eq("Dub")
    expect(page.at_css(".ui-cmd-i[href='#{customer_path(claire)}']").text).to include("1 séjour")
    expect(page.at_css(".ui-cmd-i[href='#{new_stay_path(customer_id: claire.id)}']").text.squish)
      .to eq("Nouveau séjour pour Claire Dubois")
    expect(page.css("[data-command-item]").map { |item| item["id"] }.uniq.size).to eq(page.css("[data-command-item]").size)
  end

  it "retrouve un séjour par son numéro et un écran de la compta par son nom" do
    stay = Stay.create!(customer: claire, source: "manual", status: "pending")
    sign_in user

    get command_search_path(q: "##{stay.id}")
    expect(page.at_css(".ui-cmd-i[href='#{stay_path(stay)}']")).to be_present

    get command_search_path(q: "grand livre")
    expect(page.at_css(".ui-cmd-i[href='#{finance_ledger_path}']").text).to include("Grand livre", "Toutes les écritures")
  end

  it "sans requête, propose où aller et quoi faire" do
    sign_in user

    get command_search_path

    expect(groups).to eq(["Aller à", "Actions"])
    expect(page.at_css(".ui-cmd-i[href='#{today_path}']")).to be_present
  end

  it "ne montre ni séjours ni clients à un compte qui ne les lit pas" do
    Stay.create!(customer: claire, source: "manual", status: "pending")
    sign_in User.create!(email: "com-palette@les4sources.be", password: "password123", new_interface: true,
                         access_roles: %w[communication])

    get command_search_path(q: "dubois")

    expect(groups).not_to include("Séjours", "Personnes")
    expect(response.body).not_to include("Claire")
  end

  it "pose la palette et ses déclencheurs dans la nouvelle interface seulement" do
    sign_in user
    get today_path
    expect(page.at_css(".ui-app[data-controller~='command-palette'] dialog.ui-cmd")).to be_present
    expect(page.css("[data-action='command-palette#open']").size).to eq(2)

    user.update!(new_interface: false)
    get today_path
    expect(page.at_css("dialog.ui-cmd")).to be_nil
  end

  it "présélectionne le client d'un nouveau séjour" do
    sign_in user

    get new_stay_path(customer_id: claire.id)

    expect(response).to have_http_status(:ok)
    expect(page.at_css("option[value='#{claire.id}'][selected]")).to be_present
  end
end
