# Issue tracker: GitHub

Issues and PRDs live in `predo-soares/stats` on GitHub. Use `gh` and specify `--repo predo-soares/stats` for issue and label operations.

- Read an issue with `gh issue view`, including its body, labels, and comments.
- Check existing issues before creating another for the same work.
- Publish a PRD as one GitHub issue; create implementation issues only when requested.
- For multiline content, write the exact Markdown to a file and use `--body-file`. Do not interpolate document content into shell commands.
- Apply the role labels defined in `triage-labels.md`. Create a missing mapped label when needed; avoid duplicate aliases.
- Record the published issue URL in its local document so future work can find the tracker artifact.

An issue's existence or label does not initiate implementation. Follow the user's current task and authorization.
