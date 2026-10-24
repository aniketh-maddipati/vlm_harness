"""Read members of a zip on a web server without downloading the whole archive (HTTP range requests).

The public tracking sets ship as one large zip (MOSE 26 GB, VOST 54 GB, a LaSOT category 2 to 4 GB); the mask
lab's subsets need a few hundred MB of them. Python's zipfile only needs a seekable file, so RangeFile reads the
central directory at the end and then just the members asked for. Standard library only.

    with RemoteZip(url) as z:
        names = z.namelist()
        z.extract_many([n for n in names if n.startswith("valid/")], dest)
"""
import io, os, time, urllib.request, zipfile

UA = {"User-Agent": "lumina-masklab/1 (dataset subset fetch)"}


class RangeFile(io.RawIOBase):
    def __init__(self, url, block=1 << 20):
        self.origin, self.url, self.pos, self.block = url, url, 0, block
        # One byte by range: the size from Content-Range, and the URL after redirects (Hugging Face → its CDN).
        # Works where HEAD doesn't (Google Drive's download host).
        req = urllib.request.Request(url, headers={**UA, "Range": "bytes=0-0"})
        with urllib.request.urlopen(req, timeout=60) as r:
            cr = r.headers.get("Content-Range", "")
            if r.status != 206 or "/" not in cr:
                raise IOError(f"{url}: server doesn't take range requests")
            self.size = int(cr.rsplit("/", 1)[1])
            if "huggingface.co" in url:
                self.url = r.url  # signed CDN URLs are good for a while; Drive's are not, keep asking it
        self.cache = {}
        self.fetched = 0

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = {0: off, 1: self.pos + off, 2: self.size + off}[whence]
        return self.pos

    def _get(self, start, end):
        for attempt in range(5):
            try:
                req = urllib.request.Request(self.url, headers={**UA, "Range": f"bytes={start}-{end - 1}"})
                with urllib.request.urlopen(req, timeout=120) as r:
                    data = r.read()
                self.fetched += len(data)
                return data
            except Exception as e:
                if attempt == 4:
                    raise
                if getattr(e, "code", None) in (401, 403):  # a signed CDN link ran out: ask the origin again
                    self.url = self.origin
                time.sleep(2 ** attempt)

    def _block(self, i):
        if i not in self.cache:
            if len(self.cache) > 64:
                self.cache.clear()
            s = i * self.block
            self.cache[i] = self._get(s, min(self.size, s + self.block))
        return self.cache[i]

    def readinto(self, b):
        n = min(len(b), self.size - self.pos)
        if n <= 0:
            return 0
        if n > 4 * self.block:  # a big member: one request, not through the block cache
            data = self._get(self.pos, self.pos + n)
        else:
            out, p, end = bytearray(), self.pos, self.pos + n
            while p < end:
                i = p // self.block
                blk = self._block(i)
                off = p - i * self.block
                take = min(end - p, len(blk) - off)
                out += blk[off:off + take]
                p += take
            data = bytes(out)
        b[:len(data)] = data
        self.pos += len(data)
        return len(data)


class RemoteZip(zipfile.ZipFile):
    def __init__(self, url):
        self.remote = RangeFile(url)
        super().__init__(io.BufferedReader(self.remote, buffer_size=1 << 20))

    def extract_many(self, names, dest):
        for n in names:
            out = os.path.join(dest, n)
            if os.path.exists(out) or n.endswith("/"):
                continue
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with self.open(n) as src, open(out + ".part", "wb") as dst:
                while chunk := src.read(1 << 22):
                    dst.write(chunk)
            os.replace(out + ".part", out)
