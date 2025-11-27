function update_address_book --wraps='~/.bin/maildir-rank-addr --config ~/.config/maildir-rank/config' --description 'alias update_address_book ~/.bin/maildir-rank-addr --config ~/.config/maildir-rank/config'
  ~/.bin/maildir-rank-addr --config ~/.config/maildir-rank/config $argv
        
end
