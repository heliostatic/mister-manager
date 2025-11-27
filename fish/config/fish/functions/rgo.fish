function rgo
rg --color=always --line-number --no-heading --smart-case "" |                                                                                                  fzf --ansi \
                                     --color "hl:-1:underline,hl+:-1:underline:reverse" \
                                     --delimiter : \
                                     --preview 'bat --color=always {1} --highlight-line {2}' \
                                     --preview-window 'right,60%,+{2}+3/3,~3' \
                                     --bind 'enter:become(hx {1} +{2})' 
end
