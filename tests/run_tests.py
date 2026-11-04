"""Build and test in an isolated directory without accessing video devices."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def run(args, cwd, env, expected=0):
    p = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True)
    if p.returncode != expected:
        raise AssertionError(f'{args}: expected {expected}, got {p.returncode}\n{p.stdout}\n{p.stderr}')
    return p

with tempfile.TemporaryDirectory(prefix='pro3-tests-') as td:
    work = Path(td)
    for source in ROOT.glob('*.pas'):
        shutil.copy2(source, work)
    shutil.copy2(ROOT / 'tests/controller_tests.pas', work)
    shutil.copy2(ROOT / 'tests/mock_camera.pas', work)
    env = dict(os.environ, XDG_CONFIG_HOME=str(work / 'config'))
    run(['fpc', '-B', '-dCAMERA_TEST', '-gl', '-Cr', '-Co', 'controller_tests.pas'], work, env)
    print(run(['./controller_tests'], work, env).stdout, end='')
    run(['fpc', '-B', 'linkctl.pas'], work, env)
    invalid = [
        ['focus','autp'], ['wb','nonsense'], ['exposure','invalid'],
        ['xu','0','01'], ['xu','256','01'], ['xu','2','GG'], ['xu','2','100'],
        ['xu','2','-1'], ['xu','2'], ['frame','unknown'], ['get','unknown'],
        ['pan','bad'], ['move','1'], ['preset','save','6'], ['unknown'],
        ['home','extra'], ['-u','256','info'],
    ]
    for args in invalid:
        p = run(['./linkctl','-d',str(work/'missing-device'),*args], work, env, 2)
        assert 'Cannot open' not in p.stderr, args
    print(f'PASS: {len(invalid)} malformed commands rejected before device open')
    for device in (str(work/'missing-device'), '/dev/null'):
        p = run(['./linkctl','-d',device,'info'],work,env,1)
        assert 'OK' not in p.stdout
    print('PASS: missing device and non-camera return failure')
    run(['./linkctl','help'],work,env)
    # An unwritable/non-directory configuration parent must propagate an error.
    bad_env = dict(env, XDG_CONFIG_HOME='/dev/null')
    p = subprocess.run(['./controller_tests'],cwd=work,env=bad_env,text=True,capture_output=True)
    assert p.returncode != 0 and 'Cannot create settings directory' in p.stderr
    print('PASS: settings creation failure propagates')
    # Instrument only the temporary CLI source; production builds contain no mock.
    cli = work / 'linkctl.pas'
    cli.write_text(cli.read_text().replace('ulinksettings;', 'ulinksettings, mock_camera;'))
    run(['fpc', '-B', '-dCAMERA_TEST', 'linkctl.pas'], work, env)
    prefix = ['./linkctl', '-d', '/dev/null', '-u', '4']
    for failure, args in [('read', ['get','brightness']), ('mode',['normal']),
                          ('zoom',['zoom','200'])]:
        p = run(prefix + args, work, dict(env, PRO3_TEST_FAIL=failure), 1)
        assert '\nOK\n' not in p.stdout
        if failure == 'read': assert 'Brightness:' not in p.stdout
    print('PASS: CLI read, mode, and write failures return status 1')
    p = run(prefix + ['preset','save','0'], work, bad_env, 1)
    assert 'saved to config' not in p.stdout
    print('PASS: CLI persistence failure never reports saved or OK')
    shutil.copy2(ROOT / 'tests/settings_writer.pas', work)
    run(['fpc', '-B', 'settings_writer.pas'], work, env)
    writers = [subprocess.Popen(['./settings_writer', str(slot)], cwd=work, env=env)
               for slot in (0, 1)]
    assert all(writer.wait() == 0 for writer in writers)
    run(['./settings_writer', 'check'], work, env)
    print('PASS: concurrent preset writers retain both slots')
    shutil.copy2(ROOT / 'tests/preview_retry_tests.pas', work)
    run(['fpc', '-B', 'preview_retry_tests.pas'], work, env)
    print(run(['./preview_retry_tests'], work, env).stdout, end='')
    shutil.copy2(ROOT / 'tests/preview_tests.lpr', work)
    (work / 'preview_tests.lpi').write_text("""<?xml version="1.0"?>
<CONFIG><ProjectOptions><Version Value="12"/><RequiredPackages>
<Item><PackageName Value="LCL"/></Item></RequiredPackages><Units>
<Unit><Filename Value="preview_tests.lpr"/><IsPartOfProject Value="True"/></Unit>
</Units></ProjectOptions><CompilerOptions><Version Value="11"/>
<Target><Filename Value="preview_tests"/></Target><SearchPaths>
<UnitOutputDirectory Value="preview-units"/></SearchPaths>
<Other><CustomOptions Value="-dCAMERA_TEST -gl -Cr"/></Other>
</CompilerOptions></CONFIG>""")
    run(['lazbuild', '--widgetset=nogui', 'preview_tests.lpi'], work, env)
    print(run(['./preview_tests'], work, env).stdout, end='')
    clean_root = work / 'clean-project'
    (clean_root / 'scripts').mkdir(parents=True)
    (clean_root / 'lib/x86_64-linux/gtk2').mkdir(parents=True)
    shutil.copy2(ROOT / 'scripts/clean.py', clean_root / 'scripts/clean.py')
    for name in ('insta360linkgui', 'linkctl', 'sample.o', 'sample.ppu',
                 'lib/x86_64-linux/gtk2/umainform.o',
                 'lib/x86_64-linux/gtk2/insta360linkgui.compiled'):
        (clean_root / name).touch()
    for name in ('umainform.pas', 'insta360linkgui.res', 'umainform.lfm'):
        (clean_root / name).write_text('preserve source/resource')
    run(['python3', 'scripts/clean.py'], clean_root, env)
    assert not (clean_root / 'insta360linkgui').exists()
    assert not list((clean_root / 'lib').rglob('*.o'))
    assert not list((clean_root / 'lib').rglob('*.compiled'))
    assert (clean_root / 'insta360linkgui.res').read_text() == 'preserve source/resource'
    print('PASS: clean removes GUI/CLI products and preserves resources')
print('All hardware-independent regression checks passed.')
