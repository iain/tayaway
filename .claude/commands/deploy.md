Deploy to production after ensuring the working tree is clean and pushed.

## Instructions

1. Run `git status` to check for uncommitted changes
2. If there are staged, unstaged, or untracked changes:
   - Stop and tell the user to commit first (suggest running `/commit`)
   - Do NOT proceed with deploy
3. Run `git status -sb` to check if the branch is ahead of the remote
4. If there are unpushed commits, ask the user for confirmation then run `git push`
5. Once the working tree is clean and all commits are pushed, run `cd backend && bundle exec cap production deploy`
6. Report the result to the user

## Important

- Never deploy with uncommitted changes — always stop and ask the user to commit first
- Never force push
- Always confirm before pushing to remote
- If the deploy command fails, show the error output and suggest next steps
