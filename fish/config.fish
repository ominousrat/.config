source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

# Added by LM Studio CLI (lms)
set -gx PATH $PATH /home/rat/.lmstudio/bin
# End of LM Studio CLI section

# add experimental features to torch
set -x TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL 1

fnm env --use-on-cd | source
fnm env --use-on-cd | source
