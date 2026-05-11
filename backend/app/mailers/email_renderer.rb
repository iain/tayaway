# frozen_string_literal: true

require "erb"

module Mailers
  # Shared layout + content helpers for outbound email. Both `Mailers::*`
  # auth flows and `Notifications::Kinds::*` notifications go through this
  # so the visual shell (table-based HTML, palette, button styling)
  # stays in one place. Kinds compose `html_body` from the small set of
  # helpers below and pass a plain-text heredoc as `text_body`; the
  # renderer wraps the HTML in the layout and assembles the Mail::Message.
  module EmailRenderer
    PALETTE = {
      heading: "#18181b",
      body: "#52525b",
      muted: "#a1a1aa",
      accent: "#2563eb"
    }.freeze

    class << self
      def build_message(to:, subject:, text_body:, html_body:, unsubscribable: false)
        message = Mail.new
        message.to to
        message.subject subject
        Mailers::Base.apply_sender_headers(message, unsubscribable: unsubscribable)

        text = Mail::Part.new
        text.body = text_body
        message.text_part = text

        html = Mail::Part.new
        html.content_type = "text/html; charset=UTF-8"
        html.body = wrap_html(html_body)
        message.html_part = html

        message
      end

      def heading(text)
        %(<h1 style="margin:0 0 16px;font-size:24px;color:#{PALETTE[:heading]};">#{escape(text)}</h1>)
      end

      # @param style [Symbol] :intro (default — large bottom margin),
      #   :tight (small bottom margin for stacked lines), :highlight
      #   (larger and bolder for a callout line)
      # @param raw [Boolean] true to skip escaping. Use when the caller
      #   needs inline tags like <strong>; the caller is then responsible
      #   for escaping any user-supplied substrings inside.
      def paragraph(text, style: :intro, raw: false)
        body = raw ? text : escape(text)
        %(<p style="#{paragraph_style(style)}">#{body}</p>)
      end

      def button(text:, href:)
        %(<a href="#{escape(href)}" style="display:inline-block;background-color:#{PALETTE[:accent]};color:#ffffff;font-size:16px;font-weight:600;text-decoration:none;padding:12px 32px;border-radius:6px;">#{escape(text)}</a>)
      end

      # "Or copy and paste this link:" plus a wrapped link to the same URL.
      # Designed to sit immediately under a button as a fallback for clients
      # that strip the button styling.
      def muted_link(prefix:, href:)
        h_href = escape(href)
        %(<p style="margin:32px 0 0;font-size:13px;color:#{PALETTE[:muted]};line-height:1.5;">#{escape(prefix)}<br><a href="#{h_href}" style="color:#{PALETTE[:accent]};word-break:break-all;">#{h_href}</a></p>)
      end

      def footer(text)
        %(<p style="margin:24px 0 0;font-size:13px;color:#{PALETTE[:muted]};">#{escape(text)}</p>)
      end

      def escape(text)
        ERB::Util.h(text)
      end

      private

      def paragraph_style(style)
        case style
        when :intro
          "margin:0 0 32px;font-size:16px;color:#{PALETTE[:body]};line-height:1.5;"
        when :tight
          "margin:0 0 8px;font-size:16px;color:#{PALETTE[:body]};line-height:1.5;"
        when :highlight
          "margin:0 0 24px;font-size:20px;font-weight:600;color:#{PALETTE[:heading]};"
        else
          raise ArgumentError, "Unknown paragraph style: #{style.inspect}"
        end
      end

      def wrap_html(content)
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head><meta charset="UTF-8"></head>
          <body style="margin:0;padding:0;background-color:#f4f4f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
            <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f4f5;padding:40px 0;">
              <tr><td align="center">
                <table width="480" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:8px;padding:40px;">
                  <tr><td style="text-align:center;">
                    #{content}
                  </td></tr>
                </table>
              </td></tr>
            </table>
          </body>
          </html>
        HTML
      end
    end
  end
end
