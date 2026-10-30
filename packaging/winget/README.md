# Listing Chapterly on winget

These files let people install Chapterly with:

    winget install HansDeKryger.Chapterly

winget only lists apps through a pull request to Microsoft's
[winget-pkgs](https://github.com/microsoft/winget-pkgs) repository, so this is
done by hand once per release.

## For each release

1. Publish the GitHub release (for example `v1.2.0`) with the installer from
   the `chapterly-windows-setup` build artifact attached, named exactly
   `Chapterly-Setup-1.2.0.exe`.
2. Copy this folder's `1.2.0` folder to a new one named after the version,
   and change `PackageVersion`, the installer address and the release notes
   address in the three files.
3. Get the installer's fingerprint in PowerShell and put it in
   `InstallerSha256` in the `.installer.yaml` file:

       (Get-FileHash .\Chapterly-Setup-1.2.0.exe -Algorithm SHA256).Hash

4. Check the files (needs winget on your PC):

       winget validate --manifest .\1.2.0

   You can also try installing from them:

       winget install --manifest .\1.2.0

5. Fork microsoft/winget-pkgs on GitHub, put the three files in
   `manifests/h/HansDeKryger/Chapterly/1.2.0/`, and open a pull request.
   Microsoft's checks run on it; once it is merged, `winget install` works.

From the second release on, Microsoft's `wingetcreate` tool can do steps 2 to
5 in one go:

    wingetcreate update HansDeKryger.Chapterly --version 1.3.0 --urls <installer address> --submit
