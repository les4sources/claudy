require "rails_helper"

# Epic #126, Phase 2 — code à usage unique du portail.
RSpec.describe PortalOtp, type: :model do
  it "émet un code à 6 chiffres, haché, valable 15 minutes" do
    otp, code = PortalOtp.issue!("Ana@Example.COM")

    expect(code).to match(/\A\d{6}\z/)
    expect(otp.email).to eq("ana@example.com")
    expect(otp.code_digest).not_to include(code)
    expect(otp.expires_at).to be_within(5.seconds).of(15.minutes.from_now)
  end

  it "brûle les codes précédents : un seul code valide à la fois" do
    _first, first_code = PortalOtp.issue!("ana@example.com")
    _second, second_code = PortalOtp.issue!("ana@example.com")

    expect(PortalOtp.verify("ana@example.com", first_code)).to be_nil
    expect(PortalOtp.verify("ana@example.com", second_code)).to be_present
  end

  it "consomme le code au premier succès — il ne resert jamais" do
    _otp, code = PortalOtp.issue!("ana@example.com")

    expect(PortalOtp.verify("ana@example.com", code)).to be_present
    expect(PortalOtp.verify("ana@example.com", code)).to be_nil
  end

  it "compte les tentatives et brûle le code à la 5e" do
    otp, code = PortalOtp.issue!("ana@example.com")

    4.times { expect(PortalOtp.verify("ana@example.com", "000000")).to be_nil }
    expect(otp.reload.attempts).to eq(4)
    expect(otp).not_to be_consumed

    PortalOtp.verify("ana@example.com", "000000")
    expect(otp.reload).to be_consumed
    expect(PortalOtp.verify("ana@example.com", code)).to be_nil
  end

  it "refuse un code expiré" do
    otp, code = PortalOtp.issue!("ana@example.com")
    otp.update!(expires_at: 1.second.ago)

    expect(PortalOtp.verify("ana@example.com", code)).to be_nil
  end

  it "ne confond pas deux emails" do
    _otp, code = PortalOtp.issue!("ana@example.com")

    expect(PortalOtp.verify("bruno@example.com", code)).to be_nil
  end
end
