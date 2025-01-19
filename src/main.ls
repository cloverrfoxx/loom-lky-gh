/* -=-= Loom Build System =-
 * Like makefiles, but for LuckyScript!
 */

/* -= logic starts here =- */

/*
{
    "all": {
        "dependencies": [
            "test"
        ]
    },
    "test": {
        "dependencies": [
            "test.ls"
        ],
        "commands": [
            "lky /root/LuckyScript/loom/test/test.ls -o /root/LuckyScript/loom/test/test"
        ]
    }
}
*/

import_code('/root/foxlib/json.so');

getPath(fpath) = {
    fpath = fpath.split('/');
    cpath = globals.currPath.split('/');
    if fpath[0] == '' cpath=[''];
    if cpath.join('/')=='/' cpath=[''];
    for p in fpath {
        if p==''
            continue
        else if p=='.' {
            check = comp.File((cpath+[p]).join('/'));
            if !check continue
        } else if p=='..' {
            check = comp.File((cpath+[p]).join('/'));
            if !check {
                cpath.pop();
                continue
            }
        };
        cpath.push(p)
    };
    cpath=cpath.join('/');
    if cpath=='' cpath='/';
    return cpath
};

runTarget(yarnball, hashes, target) = {
    if typeof(@yarnball) != 'map' return;
    if typeof(@hashes) != 'map' return;
    if typeof(@target) != 'string' return;

    if !yarnball.hasIndex(target) {
        if !globals.silent print('loom: '+target+' not found in yarnball.');
        return
    };

    yarn = yarnball[target];

    if typeof(yarn) != 'map' {
        if !globals.silent print('loom: '+target+' is not a yarn');
        return
    };

    rebuild = true;
    if yarn.hasIndex('dependencies') {
        rebuild = false;
        for dependency in yarn.dependencies {
            wait(0.02);
            if yarnball.hasIndex(dependency) {
                check = runTarget(yarnball, hashes, dependency);
                if /*!globals.keepgoing &&*/ check==null return;
                rebuild = rebuild || check
            } else {
                depPath = getPath(dependency);
                depFile = comp.File(depPath);

                if !depFile {
                    print(target+': Dependency '+dependency+' not found.');
                    return
                };
                if depFile.is_binary {
                    print(target+': Invalid dependency '+dependency+'.');
                    return
                };

                hash = md5(depFile.get_content());
                rebuild = rebuild || (!hashes.hasIndex(dependency)
                    || hashes[dependency]!=hash);
                newHashes[dependency] = hash
            }
        }
    };

    if rebuild && yarn.hasIndex('commands') {
        for command in yarn.commands {
            wait(0.02);
            args = command.split(' ');
            command = args[0];
            if command[0]=='.' || command[0]=='/' command=getPath(command)
                else command='/bin/'+command;
            args = args[1:];
            for i in range(0,args.len()-1)
                if args[i][0]!='-' args[i]=getPath(args[i]);
            args = args.join(' ');

            if !comp.File(command) {
                if !globals.silent print(target+': Command '+command+' not found');
                return false
            };

            if !globals.silent print(target+': '+command+' '+args);

            if !globals.dryrun shell.launch(command, args)
        };
        return true
    } else
        return false
};

printHelp() = print(
        'Usage: '+program_path+' [options] [yarn]...\n'
        + 'Options and arguments:\n'
        + '-?, -h, --help     : Print this help message and exit.\n'
        + '-f, --yarn    file : Read file as yarnfile.\n'
        + '-l, --hash    file : Read file as hashfile.\n'
        + '-C, --chdir folder : Change to folder before doing anything.\n'
        + '-n, --dryrun       : Don\'t run yarn traces; just echo.\n'
        + '-s, --silent       : Don\'t echo yarn traces.\n'
        + '-v, --version      : Print the version number of loom and exit.\n'
        + 'yarn               : Yarn to run'
    );

// initialize loom variables
shell=get_shell;
comp=get_shell.host_computer;
yarnfilePath = null;
hashfilePath = null;
dryrun = false;
silent = false;
yarn = 'all';

currPath = current_path();

i = 0;
while i < params.len() {
    arg = params[i];
    if arg=='-h' || arg=='-?' || arg=='--help' {
        printHelp();
        exit()

    } else if arg=='-f' || arg=='--yarn' {
        i++;
        if params.len()<=i
            exit('loom: *** File expected after '+arg+' option.')
        else
            yarnfilePath = getPath(params[i])

    } else if arg=='-l' || arg=='--hash' {
        i++;
        if params.len()<=i
            exit('loom: *** File expected after '+arg+' option.')
        else
            hashfilePath = getPath(params[i])

    } else if arg=='-C' || arg=='--chdir' {
        i++;
        if params.len()<=i
            exit('loom: *** Folder expected after '+arg+' option.')
        else {
            currPath = getPath(params[i]);
            if !comp.File(currPath)
                || !comp.File(currPath).is_folder
                exit('loom: *** Folder expected after '+arg+' option.')
        }
    } else if arg=='-n' || arg=='--dryrun' {
        dryrun = true

    } else if arg=='-s' || arg=='--silent' {
        silent = true

    } else if arg=='-v' || arg=='--version' {
        exit('loom: v0.1.1')

    } else if arg[0]!='-' {
        yarn = arg

    } else
        exit('loom: *** Unknown option: '+arg);
    i++
};

if !yarnfilePath yarnfilePath = currPath+'/build.yarn';
if !hashfilePath hashfilePath = currPath+'/.hash.yarn';

yarnfile = comp.File(yarnfilePath);
if !yarnfile 
    exit('loom: *** No yarnfile (build.yarn) found.');
yarnball = yarnfile.get_content();
if typeof(yarnball) != 'string'
    exit('loom: *** Could not read yarnfile. (Insufficient perms to read?)');
yarnball = json.Deserialize(yarnball);
if !yarnball
    exit('loom: *** No yarnball found in yarnfile.');

comp.touch(parent_path(hashfilePath), hashfilePath.split('/')[-1]);
hashfile = comp.File(hashfilePath);
if !hashfile
    exit('loom: *** No hashfile found. (Insufficient perms to create hashfile?)');
hashes = hashfile.get_content();
if typeof(hashes) != 'string'
    exit('loom: *** Could not read hashfile. (Insufficient perms to read?)');
hashes = json.Deserialize(hashes);
if !hashes hashes = {};

newHashes = hashes + {};

check = runTarget(yarnball, hashes, yarn);

newHashes = json.Serialize(newHashes, true);
if !dryrun && check != null hashfile.set_content(newHashes)