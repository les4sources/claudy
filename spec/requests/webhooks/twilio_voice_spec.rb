require "rails_helper"
require Rails.root.join("spec/support/env_helpers")

# Ligne de garde — webhook voix Twilio.
RSpec.describe "Webhook Twilio voix", type: :request do

  let(:token) { "test-auth-token" }
  let(:our_number) { "+3281123456" }
  let(:fallback) { "+32470999999" }
  let!(:role) { Role.find_or_create_by!(id: OnCall::Resolver::WATCHMAN_ROLE_ID) { |r| r.name = "Veilleur·euse" } }
  let(:ana) { Human.create!(name: "Ana", phone: "0470 11 11 11") }
  let(:bob) { Human.create!(name: "Bob", phone: "0470 22 22 22") }
  let(:today) { OnCall::Resolver.new.duty_date }
  let(:env) do
    { "TWILIO_AUTH_TOKEN" => token, "TWILIO_PHONE_NUMBER" => our_number,
      "TWILIO_FALLBACK_NUMBER" => fallback }
  end

  around { |example| with_env(env) { example.run } }

  def garde(human, status: :selected)
    HumanRole.create!(human: human, role: role, date: today, status: status)
  end

  def signed_post(path, params, signing_token: token)
    url = "http://www.example.com#{path}"
    signature = Twilio::Security::RequestValidator.new(signing_token).build_signature_for(url, params)
    post path, params: params, headers: { "X-Twilio-Signature" => signature }
  end

  def incoming(from: "+32478000000", sid: "CA123")
    signed_post "/webhooks/twilio/voice", { "CallSid" => sid, "From" => from }
  end

  def dial_status(step, status, duration: nil, sid: "CA123")
    params = { "CallSid" => sid, "From" => "+32478000000", "DialCallStatus" => status }
    params["DialCallDuration"] = duration.to_s if duration
    signed_post "/webhooks/twilio/voice/dial_status?step=#{step}", params
  end

  def twiml = Nokogiri::XML(response.body)
  def dial = twiml.at_xpath("/Response/Dial")

  describe "signature" do
    it "refuse une signature invalide (403)" do
      garde(ana)
      post "/webhooks/twilio/voice", params: { "CallSid" => "CA1", "From" => "+32478000000" },
                                     headers: { "X-Twilio-Signature" => "faux" }
      expect(response).to have_http_status(:forbidden)
      expect(PhoneCall.count).to eq(0)
    end

    it "refuse une requête sans signature (403)" do
      post "/webhooks/twilio/voice", params: { "CallSid" => "CA1" }
      expect(response).to have_http_status(:forbidden)
    end

    it "refuse une requête signée avec un autre jeton (403)" do
      signed_post "/webhooks/twilio/voice", { "CallSid" => "CA1" }, signing_token: "autre-jeton"
      expect(response).to have_http_status(:forbidden)
    end

    it "refuse tout quand le jeton n'est pas configuré (403)" do
      with_env("TWILIO_AUTH_TOKEN" => nil) { incoming }
      expect(response).to have_http_status(:forbidden)
    end

    it "accepte la variante https de l'URL (reverse proxy)" do
      garde(ana)
      params = { "CallSid" => "CA9", "From" => "+32478000000" }
      signature = Twilio::Security::RequestValidator.new(token)
                                                    .build_signature_for("https://www.example.com/webhooks/twilio/voice", params)
      post "/webhooks/twilio/voice", params: params, headers: { "X-Twilio-Signature" => signature }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "appel entrant" do
    it "compose le mobile du veilleur de garde, 18 s, et journalise l'appel" do
      garde(ana)
      incoming

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/xml")
      expect(dial["timeout"]).to eq("18")
      expect(dial["action"]).to eq("/webhooks/twilio/voice/dial_status?step=on_call")
      expect(dial.at_xpath("Number").text).to eq("+32470111111")

      call = PhoneCall.find_by!(call_sid: "CA123")
      expect(call.from_number).to eq("+32478000000")
      expect(call.on_call_human).to eq(ana)
      expect(call.attempts.first).to include("step" => "on_call", "number" => "+32470111111")
    end

    # Critique pour le coût : la jambe sortante est facturée selon le caller ID.
    it "présente TOUJOURS notre numéro +32 comme callerId, même pour un appelant étranger" do
      garde(ana)
      incoming(from: "+14155550123")
      expect(dial["callerId"]).to eq(our_number)

      dial_status("on_call", "no-answer", sid: "CA123")
      expect(dial["callerId"]).to eq(our_number)
    end

    it "ne compose rien si notre numéro Twilio n'est pas configuré" do
      garde(ana)
      with_env("TWILIO_PHONE_NUMBER" => nil) { incoming }
      expect(dial).to be_nil
      expect(twiml.at_xpath("/Response/Say")).to be_present
    end

    it "fait sonner le veilleur désigné quand ils sont plusieurs" do
      garde(ana)
      garde(bob).make_phone_holder!
      incoming
      expect(dial.xpath("Number").map(&:text)).to eq(["+32470222222"])
    end

    it "sans veilleur de garde, passe directement au secours" do
      incoming
      expect(dial.at_xpath("Number").text).to eq(fallback)
      expect(dial["action"]).to eq("/webhooks/twilio/voice/dial_status?step=fallback")
      expect(PhoneCall.last.on_call_human).to be_nil
    end

    it "sans veilleur ni secours, joue un message en français" do
      with_env("TWILIO_FALLBACK_NUMBER" => nil) { incoming }
      say = twiml.at_xpath("/Response/Say")
      expect(say["language"]).to eq("fr-FR")
      expect(twiml.at_xpath("/Response/Hangup")).to be_present
      expect(PhoneCall.last.outcome).to eq("unanswered")
    end
  end

  describe "issue du <Dial>" do
    it "raccroche et journalise quand le veilleur a répondu" do
      garde(ana)
      incoming
      dial_status("on_call", "completed", duration: 134)

      expect(twiml.at_xpath("/Response/Hangup")).to be_present
      expect(dial).to be_nil
      call = PhoneCall.last
      expect(call.outcome).to eq("answered_on_call")
      expect(call.dial_call_status).to eq("completed")
      expect(call.dial_call_duration).to eq(134)
      expect(call.attempts.first).to include("status" => "completed", "duration" => 134)
    end

    it "pas de réponse : suppléant, puis secours, puis message" do
      garde(ana)
      garde(bob, status: :backup)
      incoming

      dial_status("on_call", "no-answer")
      expect(dial.at_xpath("Number").text).to eq("+32470222222")
      expect(dial["action"]).to end_with("step=backup")

      dial_status("backup", "busy")
      expect(dial.at_xpath("Number").text).to eq(fallback)
      expect(dial["action"]).to end_with("step=fallback")

      dial_status("fallback", "no-answer")
      expect(twiml.at_xpath("/Response/Say")["language"]).to eq("fr-FR")

      call = PhoneCall.last
      expect(call.attempts.map { |a| [a["step"], a["status"]] })
        .to eq([%w[on_call no-answer], %w[backup busy], %w[fallback no-answer]])
      expect(call.outcome).to eq("unanswered")
    end

    it "journalise une réponse du secours" do
      incoming
      dial_status("fallback", "completed", duration: 12)
      expect(PhoneCall.last.outcome).to eq("answered_fallback")
    end

    it "ne recompose pas un numéro déjà essayé" do
      with_env("TWILIO_FALLBACK_NUMBER" => "+32470111111") do
        garde(ana)
        incoming
        dial_status("on_call", "no-answer")
      end
      expect(dial).to be_nil
      expect(twiml.at_xpath("/Response/Say")).to be_present
    end
  end

  describe "robustesse" do
    it "renvoie un TwiML valide (secours) si une exception survient" do
      allow(OnCall::Resolver).to receive(:new).and_raise(StandardError, "boom")
      incoming

      expect(response).to have_http_status(:ok)
      expect(dial.at_xpath("Number").text).to eq(fallback)
      expect(dial["callerId"]).to eq(our_number)
      expect(PhoneCall.find_by!(call_sid: "CA123")).to have_attributes(outcome: "error")
    end

    it "joue le message si l'exception survient sans numéro de secours" do
      allow(OnCall::Resolver).to receive(:new).and_raise(StandardError, "boom")
      with_env("TWILIO_FALLBACK_NUMBER" => nil) { incoming }
      expect(twiml.at_xpath("/Response/Say")["language"]).to eq("fr-FR")
    end
  end
end
