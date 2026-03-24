# cbr2cbz

A fast and reliable CBR to CBZ conversion tool for GNU/Linux, written in pure bash, with support for single-file and directory processing (including recursive and parallel workflows). It preserves timestamps, handles tricky filenames, skips already converted files, supports optional cleanup, and can inject `ComicInfo.xml` metadata during single-file conversion.

## Requirements

- A GNU/Linux distribution (tested on Ubuntu)
- `unrar-nonfree` for RAR5+ support and `zip` for creating CBZ files
- `nproc` or `getconf` for CPU detection (usually pre-installed)

  ```bash
  sudo apt-get install unrar-nonfree zip
  ```

## Installation

1. Clone this repository or download the `cbr2cbz.sh` script
2. Make it executable:

   ```bash
   chmod +x cbr2cbz.sh
   ```

3. (Optional) Move it to your PATH, for example:

   ```bash
   sudo mv cbr2cbz.sh /usr/local/bin/cbr2cbz
   ```

## Usage

### Convert a single CBR file

```bash
./cbr2cbz.sh file.cbr
```

### Convert a single CBR file and inject `ComicInfo.xml`

```bash
./cbr2cbz.sh --comicinfo /path/to/ComicInfo.xml file.cbr
```

### Convert all CBR files in a directory

```bash
./cbr2cbz.sh /path/to/comics
```

### Convert recursively through subdirectories

```bash
./cbr2cbz.sh -r /path/to/comics
```

### Process files in parallel

Use the `-j` or `--jobs` option to specify the number of parallel jobs (defaults to number of CPU cores):

```bash
# Use 4 parallel jobs
./cbr2cbz.sh -j 4 /path/to/comics

# Combine with recursive and cleanup
./cbr2cbz.sh -r -c -j 8 /path/to/comics
```

### Show help

```bash
./cbr2cbz.sh --help
```

### Inject ComicInfo Metadata

Use `-i` or `--comicinfo` to add a metadata XML file into the output archive as `ComicInfo.xml`.
This option is supported only when processing a single input file.
If the archive already contains `ComicInfo.xml`, the script asks whether to overwrite it.

```bash
./cbr2cbz.sh -i ./ComicInfo.xml ./issue_001.cbr
```

To skip the overwrite prompt and always replace an existing `ComicInfo.xml`, add:

```bash
./cbr2cbz.sh -i ./ComicInfo.xml --comicinfo-overwrite ./issue_001.cbr
```

### Cleanup Original Files

To automatically remove the original CBR files after successful conversion, use the `-c` or `--cleanup` flag:

```bash
# Convert and remove original CBR files
./cbr2cbz.sh -c file.cbr

# Process a directory and clean up
./cbr2cbz.sh -c /path/to/comics

# Combine with recursive processing
./cbr2cbz.sh -r -c /path/to/comics
```

> ⚠️ **Note**: The cleanup option permanently deletes the original CBR files after successful conversion. Use with caution!

## How It Works

1. Scans for CBR files in the specified location (recursively if `-r` is used)
2. Processes files in parallel (up to the number of CPU cores by default, or as specified by `-j`)
3. For each file:
   - Creates a temporary directory
   - Extracts the CBR (RAR) file contents using `unrar`
   - Optionally injects `ComicInfo.xml` when `--comicinfo` is used in single-file mode
   - Creates a new CBZ (ZIP) file with the same name
   - Preserves the original file's modification timestamp
   - If `--cleanup` is specified, removes the original CBR file
   - Cleans up temporary files
4. Shows progress and summary of processed files

## Why Convert from CBR to CBZ?

- **Open Format**: CBZ uses the standard ZIP format, which is open and widely supported
- **Better Compatibility**: Many comic book readers have better support for CBZ
- **Free Software**: Avoids dependency on proprietary RAR format

## License

This project is licensed under the MIT License

## Thanks to

This repository is based on the original work from [oogg06/cbr2cbz](https://github.com/oogg06/cbr2cbz).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
