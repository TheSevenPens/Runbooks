# Krita Dev Environment Runbook (Fedora)

A repeatable, step-by-step guide for setting up a full Krita development environment on Fedora Linux.

---

## 1. System Preparation

### Update your system

```bash
sudo dnf upgrade --refresh -y
```

### Install core development tools

```bash
sudo dnf groupinstall "Development Tools" -y
sudo dnf install cmake extra-cmake-modules git ninja-build ccache -y
```

- **ninja-build** — significantly faster than Make for large projects like Krita.
- **ccache** — caches compiled objects so subsequent rebuilds are much faster.

---

## 2. Install All Dependencies

Krita depends on Qt, KDE Frameworks, and a number of graphics/media libraries. Install everything in one command:

```bash
sudo dnf install -y \
  qt5-qtbase-devel qt5-qtbase-private-devel \
  qt5-qttools-devel qt5-qtmultimedia-devel \
  qt5-qtsvg-devel qt5-qtdeclarative-devel qt5-qtx11extras-devel \
  qt5-qtquickcontrols2-devel \
  kf5-kconfig-devel kf5-kcoreaddons-devel kf5-ki18n-devel \
  kf5-kwidgetsaddons-devel kf5-kcompletion-devel \
  kf5-kitemmodels-devel kf5-kitemviews-devel \
  kf5-kwindowsystem-devel kf5-karchive-devel \
  kf5-kcrash-devel kf5-kservice-devel \
  kf5-sonnet-devel kf5-kglobalaccel-devel \
  kf5-kguiaddons-devel kf5-kio-devel \
  boost-devel eigen3-devel exiv2-devel lcms2-devel \
  openexr-devel imath-devel fftw-devel \
  libtiff-devel libjpeg-turbo-devel turbojpeg-devel libpng-devel \
  libwebp-devel libheif-devel openjpeg-devel \
  giflib-devel quazip-qt5-devel \
  sqlite-devel libcurl-devel zlib-ng-compat-devel \
  mesa-libGL-devel mesa-libEGL-devel libXi-devel \
  freetype-devel harfbuzz-devel fontconfig-devel \
  libunibreak-devel fribidi-devel \
  python3-devel python3-sip-devel sip6 python3-pyqt5-sip \
  python3-qt5 python3-qt5-devel \
  gsl-devel poppler-qt5-devel LibRaw-devel \
  libmypaint-devel xsimd-devel \
  gdb valgrind
```

> **Note:** Package names may vary slightly across Fedora versions. If a package is not found, use `dnf search <keyword>` or `dnf provides */<filename>` to locate the correct name.

### Fedora 43+ package name changes

The package names above are verified on Fedora 43. If following older guides or references, note these renames:

| Old name | Fedora 43+ name |
|----------|-----------------|
| `curl-devel` | `libcurl-devel` |
| `zlib-devel` | `zlib-ng-compat-devel` |
| `openjpeg2-devel` | `openjpeg-devel` |
| `libraw-devel` | `LibRaw-devel` (case-sensitive) |
| `pyqt5-sip` | `python3-pyqt5-sip` |

### Header-only libraries (not in Fedora repos)

Krita requires three header-only C++ libraries from [arximboldi](https://github.com/arximboldi) that are not packaged in Fedora. Install them from source:

```bash
for lib in immer zug lager; do
  cd /tmp
  git clone --depth 1 https://github.com/arximboldi/${lib}.git
  mkdir ${lib}/build && cd ${lib}/build
  cmake .. -DCMAKE_BUILD_TYPE=Release \
    -D${lib}_BUILD_TESTS=OFF \
    -D${lib}_BUILD_EXAMPLES=OFF \
    -D${lib}_BUILD_DOCS=OFF
  sudo make install
done
```

### Verify dependencies are installed

Before continuing, confirm all packages were installed successfully:

```bash
rpm -q \
  cmake extra-cmake-modules ninja-build ccache git \
  qt5-qtbase-devel qt5-qtbase-private-devel \
  qt5-qttools-devel qt5-qtmultimedia-devel \
  qt5-qtsvg-devel qt5-qtdeclarative-devel qt5-qtx11extras-devel \
  qt5-qtquickcontrols2-devel \
  kf5-kconfig-devel kf5-kcoreaddons-devel kf5-ki18n-devel \
  kf5-kwidgetsaddons-devel kf5-kcompletion-devel \
  kf5-kitemmodels-devel kf5-kitemviews-devel \
  kf5-kwindowsystem-devel kf5-karchive-devel \
  kf5-kcrash-devel kf5-kservice-devel \
  kf5-sonnet-devel kf5-kglobalaccel-devel \
  kf5-kguiaddons-devel kf5-kio-devel \
  boost-devel eigen3-devel exiv2-devel lcms2-devel \
  openexr-devel imath-devel fftw-devel \
  libtiff-devel libjpeg-turbo-devel turbojpeg-devel libpng-devel \
  libwebp-devel libheif-devel openjpeg-devel \
  giflib-devel quazip-qt5-devel \
  sqlite-devel libcurl-devel zlib-ng-compat-devel \
  mesa-libGL-devel mesa-libEGL-devel libXi-devel \
  freetype-devel harfbuzz-devel fontconfig-devel \
  libunibreak-devel fribidi-devel \
  python3-devel python3-sip-devel sip6 python3-pyqt5-sip \
  python3-qt5 python3-qt5-devel \
  gsl-devel poppler-qt5-devel LibRaw-devel \
  libmypaint-devel xsimd-devel \
  gdb valgrind \
  | grep "not installed"
```

If there is no output, all dependencies are present. Any listed packages need to be installed before proceeding.

---

## 3. Clone Krita Source Code

Clone krita as a sibling of this runbook repository:

```bash
cd ~/Documents/GitHub
git clone https://invent.kde.org/graphics/krita.git
cd krita
```

This gives you the following layout:

```
~/Documents/GitHub/
  Krita-Runbook/     # this runbook
  krita/             # krita source
```

To check out a stable branch instead of `master`:

```bash
git checkout krita/5.2
```

To do a shallow clone (faster, less disk space):

```bash
cd ~/Documents/GitHub
git clone --depth 1 https://invent.kde.org/graphics/krita.git
```

---

## 4. Configure with CMake

Keep builds separate from source:

```bash
mkdir build && cd build
```

### Using Ninja (recommended)

```bash
cmake .. \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_PREFIX_PATH=/usr/lib64/python3.14/site-packages \
  -DBUILD_TESTING=OFF
```

### Using Make (alternative)

```bash
cmake .. \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_PREFIX_PATH=/usr/lib64/python3.14/site-packages \
  -DBUILD_TESTING=OFF
```

> **Fedora 43 note:** The `CMAKE_PREFIX_PATH` is required so that SIP can find the PyQt5 bindings at `/usr/lib64/python3.14/site-packages/PyQt5/bindings/`. Without it, the build will fail during Python plugin generation.

### Useful CMake flags

| Flag | Purpose |
|------|---------|
| `-DCMAKE_BUILD_TYPE=Debug` | Full debug symbols, no optimization |
| `-DCMAKE_BUILD_TYPE=RelWithDebInfo` | Optimized with debug info (recommended) |
| `-DKRITA_ENABLE_PYTHON=ON` | Enable Python scripting plugin support |
| `-DCMAKE_INSTALL_PREFIX=/usr/local` | Set install location |
| `-DBUILD_TESTING=ON` | Build unit tests |

---

## 5. Compile Krita

### With Ninja

```bash
ninja -j$(nproc)
```

### With Make

```bash
make -j$(nproc)
```

A full build from scratch can take 15-45 minutes depending on hardware. Subsequent rebuilds with ccache will be significantly faster.

---

## 6. Run Krita (Without Installing)

From the build directory:

```bash
./bin/krita
```

---

## 7. Install System-Wide (Optional)

### With Ninja

```bash
sudo ninja install
```

### With Make

```bash
sudo make install
```

---

## 8. Environment Variables

If you encounter runtime linking issues after installing:

```bash
export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH
```

To make this persistent, add it to `~/.bashrc` or `~/.zshrc`.

If Krita can't find its resource bundles:

```bash
export KRITA_RESOURCE_DIR=$HOME/.local/share/krita
```

---

## 9. Running Tests

First, reconfigure with `-DBUILD_TESTING=ON`, then rebuild:

```bash
cmake .. -DBUILD_TESTING=ON
ninja -j$(nproc)
ctest --output-on-failure
```

Run a specific test:

```bash
ctest -R <test_name> --output-on-failure
```

---

## 10. Debugging

### Install debugging tools

```bash
sudo dnf install gdb valgrind -y
```

### Install debug symbols for system libraries

```bash
sudo dnf debuginfo-install -y qt5-qtbase qt5-qtsvg kf5-ki18n
```

### Run Krita under GDB

```bash
gdb ./bin/krita
(gdb) run
```

After a crash, use `bt` (backtrace) to see the call stack.

### Sanitizer builds (for finding memory bugs)

```bash
cmake .. \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DECM_ENABLE_SANITIZERS="address;undefined"
ninja -j$(nproc)
```

---

## 11. Common Issues and Fixes

### Missing Qt/KF5 packages

Re-run the dependency install commands. Search for missing headers:

```bash
dnf provides */<missing-header-file>
```

### CMake can't find a dependency

Check if the `-devel` package is installed:

```bash
rpm -qa | grep <library-name>
```

### Wayland rendering glitches

Force X11 backend:

```bash
QT_QPA_PLATFORM=xcb ./bin/krita
```

### OpenGL issues

Check your GPU driver and OpenGL support:

```bash
glxinfo | grep "OpenGL version"
```

Krita requires at least OpenGL 3.0. If you are in a VM, you may need to enable 3D acceleration or use software rendering:

```bash
LIBGL_ALWAYS_SOFTWARE=1 ./bin/krita
```

### Linker errors about missing symbols

Your build tree may be stale. Clean and rebuild:

```bash
ninja clean
ninja -j$(nproc)
```

---

## 12. Keeping Your Repo Updated

```bash
cd ~/Documents/GitHub/krita
git pull --rebase
cd build
ninja -j$(nproc)
```

If the build fails after pulling, try a clean reconfigure:

```bash
rm -rf build && mkdir build && cd build
cmake .. -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=OFF
ninja -j$(nproc)
```

---

## 13. KDE Craft (Alternative Build System)

KDE provides [Craft](https://community.kde.org/Craft) as an alternative for managing builds:

- Handles all dependency management automatically
- Supports cross-platform builds (Linux, macOS, Windows)
- More complex initial setup
- Generally overkill for Fedora-native development where system packages suffice

---

## Verification Checklist

- [ ] CMake configuration completes without errors
- [ ] Build completes without errors
- [ ] Krita launches successfully (`./bin/krita`)
- [ ] Canvas renders and responds to brush strokes
- [ ] No missing library errors (`ldd ./bin/krita | grep "not found"`)
- [ ] Python scripting console works (Settings > Configure Krita > Python Plugin Manager)

---

## Useful Resources

- [Krita developer documentation](https://docs.krita.org/en/untranslatable_pages/building_krita.html)
- [Krita source repository (KDE Invent)](https://invent.kde.org/graphics/krita)
- [KDE development setup guide](https://community.kde.org/Get_Involved/development)
- [Krita bug tracker](https://bugs.kde.org/describecomponents.cgi?product=krita)
- [Krita contributor guide](https://docs.krita.org/en/contributors_manual.html)
