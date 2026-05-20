"""opus_base — helpers reutilizables para conexión y escritura segura a OPUS Módulo 1.

Copia este archivo a scripts/ de tu repo OPUS e impórtalo:

    from opus_base import OpusDB

    db = OpusDB(
        server=r"(localdb)\\OpusLocal",
        mdf=r"C:\\ECOSOFT\\PROYECTOS\\PRESUPUESTO PROGRAMABLE\\NNN NOMBRE.MDF",
        backups_dir=r"...\\backups",
    )
    db.kill_sessions()
    db.backup("PRE_MIOP")
    with db.tx() as cur:                 # transacción: commit al salir, rollback si excepción
        cur.execute("UPDATE ...")
        # verificación con asserts antes de salir del with

Requiere: pyodbc, ODBC Driver 17 for SQL Server.
Consulta la skill `opus-escritura-segura` para el protocolo completo y las trampas.
"""
from __future__ import annotations
import time, datetime, contextlib
from pathlib import Path
import pyodbc


class OpusDB:
    def __init__(self, server: str, mdf: str, backups_dir: str | None = None):
        self.server = server
        self.mdf = mdf  # nombre exacto de la BD = ruta MDF en MAYÚSCULAS
        self.backups_dir = Path(backups_dir) if backups_dir else None

    # ---- connection strings ----
    def _cs(self, db: str) -> str:
        return (f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={self.server};"
                f"DATABASE={db};Trusted_Connection=yes;")

    def connect(self, autocommit: bool = True) -> pyodbc.Connection:
        return pyodbc.connect(self._cs(self.mdf), autocommit=autocommit)

    # ---- liberar locks de OPUS ----
    def kill_sessions(self) -> int:
        """Mata las sesiones que tengan abierta la BD (libera locks de OPUS)."""
        conn = pyodbc.connect(self._cs("master"), autocommit=True)
        cur = conn.cursor()
        rows = cur.execute(
            "SELECT session_id FROM sys.dm_exec_sessions "
            "WHERE database_id=DB_ID(?) AND session_id<>@@SPID", self.mdf
        ).fetchall()
        for r in rows:
            try:
                cur.execute(f"KILL {r.session_id}")
            except Exception:
                pass
        conn.close()
        if rows:
            time.sleep(2)
        return len(rows)

    # ---- backup .bak con timestamp ----
    def backup(self, tag: str = "PRE_OP") -> Path:
        if not self.backups_dir:
            raise ValueError("backups_dir no configurado")
        self.backups_dir.mkdir(parents=True, exist_ok=True)
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        # nombre amigable: usa el basename del MDF
        base = Path(self.mdf).stem.replace(" ", "_")
        bak = self.backups_dir / f"{base}_{tag}_{ts}.bak"
        conn = self.connect(autocommit=True)
        cur = conn.cursor()
        cur.execute(f"BACKUP DATABASE [{self.mdf}] TO DISK = ? WITH FORMAT, INIT, NAME = ?",
                    str(bak), tag)
        while cur.nextset():
            pass
        conn.close()
        if not bak.exists() or bak.stat().st_size == 0:
            raise RuntimeError(f"Backup falló o quedó vacío: {bak}")
        return bak

    # ---- transacción segura ----
    @contextlib.contextmanager
    def tx(self):
        """Context manager: commit al salir limpio, rollback ante cualquier excepción."""
        conn = pyodbc.connect(self._cs(self.mdf), autocommit=False)
        cur = conn.cursor()
        try:
            yield cur
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    # ---- utilidades ----
    def next_id(self, table: str, pk: str) -> int:
        conn = self.connect()
        v = conn.cursor().execute(f"SELECT MAX({pk}) FROM {table}").fetchone()[0]
        conn.close()
        return (v or 0) + 1

    def importe(self) -> float:
        conn = self.connect()
        v = conn.cursor().execute("SELECT Importe FROM ProyectoPropuesta").fetchone()[0]
        conn.close()
        return float(v or 0)
