# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::OnNewSession do
  describe ".call" do
    let(:user) { TestFactories.user }
    let(:browser_info) { { browser_name: "Firefox", os_name: "macOS" } }
    let(:geo) { { city: "Amsterdam", country: "NL" } }

    def stored_session(browser_name:, country:, created_at: Time.now)
      TestFactories.session(user: user).tap do |row|
        DB[:sessions].where(id: row[:id]).update(
          browser_name: browser_name, country: country, created_at: created_at
        )
      end
    end

    it "fires when the (browser, country) combination is novel" do
      session = stored_session(browser_name: "Firefox", country: "NL")

      described_class.call(user_id: user[:id], session_id: session[:id], browser_info: browser_info, geo: geo)

      expect(DB[:notifications].where(user_id: user[:id], kind: "new_session").count).to eq(1)
    end

    it "stays silent when the same (browser, country) was seen recently" do
      prior = stored_session(browser_name: "Firefox", country: "NL", created_at: Time.now - (5 * 86_400))
      current = stored_session(browser_name: "Firefox", country: "NL")
      expect(prior[:id]).not_to eq(current[:id])

      described_class.call(user_id: user[:id], session_id: current[:id], browser_info: browser_info, geo: geo)

      expect(DB[:notifications].count).to eq(0)
    end

    it "fires when the prior session is older than 30 days" do
      stored_session(browser_name: "Firefox", country: "NL", created_at: Time.now - (60 * 86_400))
      current = stored_session(browser_name: "Firefox", country: "NL")

      described_class.call(user_id: user[:id], session_id: current[:id], browser_info: browser_info, geo: geo)

      expect(DB[:notifications].count).to eq(1)
    end
  end
end
