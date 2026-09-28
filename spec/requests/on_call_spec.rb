require "rails_helper"
require Rails.root.join("spec/support/env_helpers")

# Ligne de garde — écran admin.
RSpec.describe "Ligne de garde (admin)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "garde@les4sources.be", password: "password123") }
  let!(:role) { Role.find_or_create_by!(id: OnCall::Resolver::WATCHMAN_ROLE_ID) { |r| r.name = "Veilleur·euse" } }
  let(:ana) { Human.create!(name: "Ana", phone: "0470 11 11 11") }
  let(:bob) { Human.create!(name: "Bob", phone: "0470 22 22 22") }
  let(:today) { OnCall::Resolver.new.duty_date }

  before { sign_in user }

  it "montre qui décroche maintenant et les derniers appels" do
    HumanRole.create!(human: ana, role: role, date: today, status: :selected)
    PhoneCall.create!(call_sid: "CA1", from_number: "+32478000000", on_call_human: ana,
                      outcome: "answered_on_call",
                      attempts: [{ "step" => "on_call", "human_id" => ana.id, "number" => ana.phone,
                                   "status" => "completed", "duration" => 42 }])

    get on_call_path

    expect(response).to have_http_status(:ok)
    now = Nokogiri::HTML(response.body).at_css("#on-call-now").text
    expect(now).to include("Ana", "+32 470 11 11 11")
    calls = Nokogiri::HTML(response.body).at_css("#on-call-calls").text
    expect(calls).to include("+32 478 00 00 00", "Répondu par le veilleur", "Veilleur (Ana) : completed · 42 s")
  end

  it "désigne le veilleur qui tient le téléphone" do
    HumanRole.create!(human: ana, role: role, date: today, status: :selected)
    bob_role = HumanRole.create!(human: bob, role: role, date: today, status: :selected)

    patch phone_holder_on_call_path(human_role_id: bob_role.id)

    expect(response).to redirect_to(on_call_path)
    expect(OnCall::Resolver.new(duty_date: today).on_call).to eq(bob)
  end

  it "enregistre l'heure de bascule et refuse une heure hors bornes" do
    patch on_call_path, params: { handover_hour: "8" }
    expect(OnCall::Config.handover_hour).to eq(8)

    patch on_call_path, params: { handover_hour: "25" }
    expect(flash[:alert]).to be_present
    expect(OnCall::Config.handover_hour).to eq(8)
  end
end
