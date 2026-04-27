# frozen_string_literal: true

server "tayaway.nl", user: fetch(:deploy_user), roles: %w[app db web], ssh_options: { port: 50022 }
