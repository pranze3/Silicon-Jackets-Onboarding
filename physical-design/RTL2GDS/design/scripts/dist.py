#!/usr/bin/env python3

###############################################################################
#  Copyright (C) 2024 Cadence Design Systems, Inc.                            #
#  All Rights Reserved.                                                       #
#  CCRNI-0013                                                                 #
#                                                                             #
# This script is AEWare, provided as an example of how to perform specialized #
# tasks within SoC Encounter.  It is not supported via the Cadence Hotline    #
# nor the CCR system.                                                         #
#                                                                             #
# This work is Cadence intellectual property and may under no circumstances   #
# be given to third parties, neither in original nor in modified versions,    #
# without explicit written permission from Cadence                            #
#                                                                             #
# The information contained herein is the proprietary and confidential        #
# information of Cadence or its licensors, and is supplied subject to, and    #
# may be used only by Cadence's customers in accordance with, a previously    #
# executed license and maintenance agreement between Cadence and its          #
# customer.                                                                   #
###############################################################################

import getpass, json, logging, os, re, shlex, signal, socket, stat, subprocess, sys, threading, time, traceback
from datetime import datetime

# Configure script and distribution specific parameters. The supported
# parameters are specific to each distribution method, but there are a small set
# of common parameters which can be set or overridden for any method.
class DefaultConfig(object):
  # Include debug messages in the log and always generate a report (lsf-only)
  debug = False
  # Email address to send a copy of the report to when complete (bhist for lsf,
  # reports have not been implemented for other methods)
  email_addr = None
  # Create a run script instead of passing the command directly, this is useful
  # to work around quoting issues and too-long command lines
  use_run_script = False
  # Copy environment variables into distributed shell, this is normally done by
  # the distribution mechanism so setting to False does not give a clean
  # environment
  copy_environment = False
  # Regexp defining which environment variables to copy into distributed shell.
  # Don't use .* to copy all environment variables as that will also copy $HOST
  # and other variables which will cause failures
  copy_environment_variables = re.compile(r'^(CBRS_.*|CEREBRUS_.*|DISTPY_.*|FLOWTOOL_.*)$', re.ASCII)
  # How often to poll the status of the task, initial timeout in seconds
  status_timeout_initial = 10
  # How often to poll the status of the task, time in seconds to increase the
  # timeout by for each poll
  status_timeout_increment = 10
  # How often to poll the status of the task, maximum timeout in seconds
  status_timeout_limit = 180

class LocalDistConfig(DefaultConfig):
  # Capture the entire process STDOUT to the dist log; this is written after the
  # task has exited and can cause large memory usage as it is stored in memory.
  # Using tool logfiles is preferred. dist.py always captures STDERR.
  capture_stdout = False

class SshDistConfig(DefaultConfig):
  ssh_exe = "ssh"
  ssh_host = "< PLACEHOLDER: DIST HOST >"
  copy_environment = True

class LsfDistConfig(DefaultConfig):
  queue = "< PLACEHOLDER: DIST QUEUE STRING >"
  bsub_exe = "bsub"
  bsub_args = "< PLACEHOLDER: DIST ARGS STRING >"
  bsub_resource = "< PLACEHOLDER: DIST RESOURCE STRING >"

class SgeDistConfig(DefaultConfig):
  queue = "< PLACEHOLDER: DIST QUEUE STRING >"
  qsub_exe = "qsub"
  qsub_args = "< PLACEHOLDER: DIST ARGS STRING >"
  use_run_script = True

class NbDistConfig(DefaultConfig):
  target = "< PLACEHOLDER: DIST TARGET STRING >"
  nb_exe = "nb"
  nb_run_args = "< PLACEHOLDER: DIST ARGS STRING >"
  nb_run_resource = "< PLACEHOLDER: DIST RESOURCE STRING >"

# Configure flow-specific parameters based on environment variables. You can use
# any environment variable (not just FLOWTOOL_*) to refine the parameters used.
# This is an exact match of value with no wildcard support. Special values are:
#   * True: will match "1", "yes", "true", "True"
#   * False: will match "0", "no", "false", "False"
#   * None: environment variable not set
#   * "": will match empty string
# Environment variables are processed in alphabetical order with later values
# overwriting earlier (or default) values.
class FlowConfig(object):
  default = {
    # distribution method "local", "ssh", "lsf", "sge", "nb"
    "dist": "lsf",
    # number of cores to request (no impact for "local" or "ssh" dist)
    "threads": 1,
    # amount of RAM in MB to request (no impact for "local" or "ssh" dist)
    "memory_mb": 10000
  }
  FLOWTOOL_CHILD_OF_FLOW_PATH = {
    # When FLOWTOOL_CHILD_OF_FLOW_PATH environment variable matches one of the
    # values below, the configuration will be updated as shown
    "syn_generic": {"threads": 2},
    "syn_map": {"threads": 2},
    "syn_opt": {"threads": 2},
    "prects": {"threads": 2},
    "cts": {"threads": 2},
    "postcts": {"threads": 2},
    "route": {"threads": 2, "memory_mb": 15000},
    "postroute": {"threads": 2, "memory_mb": 15000},
    "sta": {"threads": 2},
    "route.report_postroute": {"threads": 2},
    "postroute.report_postroute": {"threads": 2}
  }
  FLOWTOOL_INTERACTIVE = {
    # If we are using flowtool -interactive (which sets the FLOWTOOL_INTERACTIVE
    # environment variable to "1") set interactive mode and don't force-kill
    # (kill -9) the task if Ctrl+C is used
    True: {"interactive": True, "force_kill_after_interrupt": False}
  }
  FLOWTOOL_IS_TRUNK = {
    # If we are a main trunk flow (FLOWTOOL_IS_TRUNK environment variable is set
    # to "1"), run the task on the local machine instead of in the farm. Useful
    # if flowtool is already distributed but you want reporting to run elsewhere
    #True: {"dist": "local"}
  }
  FLOWTOOL_TOOL = {
    # If the tool (FLOWTOOL_TOOL environment variable) is "flowtool", run the
    # task on the local machine as flowtool does not require large resources
    "flowtool": {"dist": "local"},
    # If the tool (FLOWTOOL_TOOL environment variable) is "cerebrus_runner",
    # allow the task to keep running if dist.py is killed so that any monitored
    # tasks can continue to run
    "cerebrus_runner": {"pass_signals_to_task": False}
  }

###############################################################################
#
# End of configuration, dist script follows. You can stop reading here
#
###############################################################################

class DistManager(object):
  """Main manager class for dist.py. Attaches signal handlers, polls status in a
  thread, handles timeouts and contains all the general business logic which is
  shared between the distribution methods"""
  _methods = {}

  if sys.version_info < (3, 2):
    raise RuntimeError('dist.py requires python 3.2 or above, found ' + sys.version)

  @classmethod
  def registerMethod(cls, method, distClass, default=False):
    """Register a distribution method name and class, default is the class which
    is used for misspelt or unknown distribution methods"""
    cls._methods[method] = distClass
    if default:
      cls._methods[None] = distClass

  def __init__(self, argv):
    """Initialize and run the distributed process"""
    self._config = {}
    self._dist = None
    command = argv[0]
    argv.pop(0)
    if len(argv) == 0 or argv == '' or argv is None:
      raise RuntimeError('command to run is missing e.g. ' + command + ' sleep 10')
    self._commandToRun = argv
    self.pendingSignalsLock = threading.RLock()
    self.pendingSignals = []
    self.processFinished = threading.Event()
    self.messagePending = threading.Event()
    self._previousSignalHandlers = {}
    self._killTimer = None

    self._configureLogging()
    self._calculateConfig()
    if self._config.get('use_run_script', False):
      self._createRunScript()
    elif self._config.get('copy_environment', False):
      self._copyEnvironmentDirectly()
    thread = self._createMonitorThread()
    thread.start()
    if self._config['pass_signals_to_task']:
      self._attachSignalHandlers()
    self._startProcess()
    thread.join()
    self._detachSignalHandlers()
    exitCode = self._reportResult()
    logging.shutdown()
    exit(exitCode)

  def getMethod(self, method):
    """Lookup the class for a distribution method"""
    if method in DistManager._methods:
      return DistManager._methods[method]
    elif None in DistManager._methods:
      return DistManager._methods[None]
    else:
      return None

  def _configureLogging(self):
    """Initialize logging and start the logfile"""
    logPrefix = os.environ.get('FLOWTOOL_LOG_PREFIX', '')
    if os.path.isdir(logPrefix):
      filename = os.path.join(logPrefix, 'dist.log')
    elif logPrefix == '':
      filename = 'dist.log'
    else:
      filename = logPrefix + '.dist'
    self._logFilename = self._uniqueFilename(filename)
    # Take our initial debug level from DefaultConfig, configureConfig will
    # update this level later based on the merged config
    if DefaultConfig.debug:
      initialLevel = logging.DEBUG
    else:
      initialLevel = logging.INFO
    # Create a dist.log file
    logging.basicConfig(level=initialLevel,
        format='[%(asctime)s %(levelname)8s] %(message)s',
        datefmt='%m/%d %H:%M:%S',
        filename=self._logFilename,
        filemode='w')
    # Also log to stdout
    self._consoleLogger = logging.StreamHandler(sys.stdout)
    self._consoleLogger.setLevel(logging.INFO)
    self._consoleLogger.setFormatter(logging.Formatter('  DIST: [%(levelname)8s] %(message)s'))
    logging.getLogger('').addHandler(self._consoleLogger)
    sys.excepthook = self._logException

  def _logException(self, type, value, tb):
    """Top-level exception handler so that we log exceptions"""
    # Make sure any existing log output is flushed before outputting the error
    [handler.flush() for handler in logging.getLogger("").handlers]
    # Log exceptions to the log file, but no need to repeat them to the console
    previousLevel = self._consoleLogger.level
    self._consoleLogger.setLevel(logging.CRITICAL)
    logging.error("".join(traceback.format_exception(type, value, tb)).strip())
    self._consoleLogger.setLevel(previousLevel)
    sys.__excepthook__(type, value, tb)

  def _calculateConfig(self):
    """Merge the FlowConfig environment variables and Dist*Config classes to
    produce a finalized config and selected distribution method. The finalized
    config is set in self._config"""
    # Backwards compatibility
    # FLOWTOOL_CHILD_OF_FLOW_PATH introduced in Flowtool 21.11-s004
    if 'FLOWTOOL_CHILD_OF_FLOW_PATH' not in os.environ and 'FLOWTOOL_FLOW_PATH' in os.environ:
      path = os.environ.get('FLOWTOOL_FLOW_PATH', '')
      childOf = os.environ.get('FLOWTOOL_FLOW_CHILD_OF', '')
      path = '.'.join(self._parseTclList(path))
      if childOf != '':
        path = self._parseTclList(childOf)[-1].replace('flow:','') + '.' + path
      os.environ['FLOWTOOL_CHILD_OF_FLOW_PATH'] = path
    # Apply the FlowConfig by starting with "default" and then checking the
    # remaining variables against environment variables, updating as we match.
    # The order of merging is alphabetical by environment variable name (due to
    # dir() using a dict which is unordered, this could be fixed by using
    # __prepare__ but it would add unnecessary complexity to the config classes)

    # Apply some initial default values which will allow the rest of the
    # script to assume these are defined always, in case they get deleted from
    # the config classes above
    defaultConfig = {
      # Include debug messages in the log and always generate a report (extra
      # debugging)
      'debug': False,
      # Default distribution method: local, ssh, lsf, sge, nb
      'dist': 'local',
      # Is this an interactive task where stdin, stdout, stderr need to be
      # passed through?
      'interactive': False,
      # Email address to send a copy of the report to when complete (bhist for
      # lsf, reports have not been implemented for other methods)
      'email_addr': None,
      # Create a run script instead of passing the command directly, this is
      # useful to work around quoting issues and too-long command lines
      'use_run_script': False,
      # Copy environment variables into distributed shell, this is normally done
      # by the distribution mechanism so setting to False does not give a clean
      # environment
      'copy_environment': False,
      # Regexp defining which environment variables to copy into distributed
      # shell.  Don't use .* to copy all environment variables as that will also
      # copy $HOST and other variables which will cause failures
      'copy_environment_variables': re.compile(r'^(CBRS_.*|CEREBRUS_.*|DISTPY_.*|FLOWTOOL_.*)$', re.ASCII),
      # Number of threads/cores/cpus to request, not used by all distribution
      # methods
      'threads': 1,
      # Amount of RAM to request in MB, not used by all distribution methods
      'memory_mb': 1000,
      # pass signals (ctrl+C, etc) through to the process. Setting to False does
      # not guarantee that signals will not be passed for all distribution
      # methods (e.g. in interactive mode we usually do not perform the required
      # shell manipulation to stop the child receiving signals). Setting to
      # False will also prevent force_kill_after_interrupt from functioning.
      'pass_signals_to_task': True,
      # Send a SIGKILL (cannot be ignored) after a SIGINT (ctrl+C) or SIGTERM
      # (kill command)
      'force_kill_after_interrupt': True,
      # Time to wait after SIGINT or SIGTERM before sending SIGKILL
      'force_kill_timeout': 600,
      # How long to poll the status of the task, initial timeout in seconds
      'status_timeout_initial': 10,
      # How long to poll the status of the task, time in seconds to increase the
      # timeout by for each poll
      'status_timeout_increment': 10,
      # How long to poll the status of the task, maximum timeout in seconds
      'status_timeout_limit': 180
    }
    config = {}
    flowConfig = {}
    for key in dir(FlowConfig):
      if not key.startswith('__') and not callable(getattr(FlowConfig, key)):
        flowConfig[key] = getattr(FlowConfig, key)
    if 'default' in flowConfig:
      config.update(flowConfig['default'])
      del flowConfig['default']
    for key, values in flowConfig.items():
      env = os.environ.get(key, None)
      normalizedValues = values.copy()
      # Copy any non-string (e.g. number) keys into strings as environment
      # variables will be strings and won't match the number otherwise
      for k, v in values.items():
        if not isinstance(k, str) and k is not True and k is not False and k is not None:
          strk = str(k)
          if strk not in normalizedValues:
            normalizedValues[strk] = v
      if None in normalizedValues and env is None:
        logging.debug('FlowConfig matched {key} with None, adding to config: {config}'.format(key=key, config=normalizedValues[None]))
        config.update(normalizedValues[None])
      elif True in normalizedValues and env in ['1', 'yes', 'true', 'True']:
        logging.debug('FlowConfig matched {key} with True, adding to config: {config}'.format(key=key, config=normalizedValues[True]))
        config.update(normalizedValues[True])
      elif False in normalizedValues and env in ['0', 'no', 'false', 'False']:
        logging.debug('FlowConfig matched {key} with False, adding to config: {config}'.format(key=key, config=normalizedValues[False]))
        config.update(normalizedValues[False])
      elif env in normalizedValues:
        logging.debug('FlowConfig matched {key} with "{value}", adding to config: {config}'.format(key=key, value=env, config=normalizedValues[env]))
        config.update(normalizedValues[env])
    mergedConfig = {}
    mergedConfig.update(defaultConfig);
    mergedConfig.update(flowConfig);
    if 'debug' in mergedConfig:
      # The config may have changed the debug flag, update the logger level
      if mergedConfig['debug']:
        logging.getLogger('').setLevel(logging.DEBUG)
      else:
        logging.getLogger('').setLevel(logging.INFO)
    logging.debug('FlowConfig parsed as {config}'.format(config=config))
    # Update the config based on the dist method to populate the full config;
    # this is allowed to be recursive where a dist method changes 'dist'
    # (e.g. ssh could change to local if the host is unavailable)
    method = mergedConfig['dist']
    iterMax = 0
    while True:
      if method is None:
        raise ValueError('\'dist\' has been configured to "None", check the FlowConfig section')
      previousMethod = method
      methodCls = self.getMethod(method)
      if methodCls is None:
        raise ValueError('"{dist}" is an unknown \'dist\' method, check the FlowConfig section'.format(dist=method))
      newConfig = methodCls.calculateConfig(defaultConfig, config)
      method = newConfig['dist']
      if 'debug' in newConfig:
        # The config may have changed the debug flag, update the logger level
        if newConfig['debug']:
          logging.getLogger('').setLevel(logging.DEBUG)
        else:
          logging.getLogger('').setLevel(logging.INFO)
      if method == previousMethod:
        logging.debug('\'dist\' method "{method}" has updated config to {config}'.format(method=method, config=newConfig))
        config = newConfig
        break
      else:
        logging.debug('\'dist\' method "{previous}" has changed \'dist\' to "{method}"; returned {config}'.format(previous=previousMethod, method=method, config=newConfig))
        config['dist'] = method
        iterMax += 1
        if iterMax > 10:
          raise ValueError('*DistConfig section changes \'dist\' method too many times, was "{previous}" now "{now}". Try reducing number of times "dist" is set inside *DistConfig'.format(previous=previousMethod, now=method))
    self._config = config
    # Configure some environment to make it easier to process later
    if 'threads' in self._config:
      # Backwards compatibility with previous dist.py script
      os.environ['FLOWTOOL_NUM_CPUS'] = str(self._config['threads'])
      os.environ['DISTPY_NUM_CPUS'] = str(self._config['threads'])
      os.environ['DISTPY_MEMORY_MB'] = str(self._config['memory_mb'])
    taskName = os.path.basename(os.path.abspath(os.environ.get('FLOWTOOL_DIR', '.')))
    if os.environ.get('FLOWTOOL_RUN_TAG', '') != '':
      taskName += '/' + os.environ['FLOWTOOL_RUN_TAG']
    taskName += '-' + os.environ.get('FLOWTOOL_CHILD_OF_FLOW_PATH', '')
    self._config['task_name'] = taskName

  def _getEnvironmentToCopy(self):
    env = {}
    for name, value in os.environ.items():
      if re.search(self._config['copy_environment_variables'], name):
        env[name] = value
    return env

  def _copyEnvironmentDirectly(self):
    env = ['/usr/bin/env']
    for name, value in self._getEnvironmentToCopy().items():
      env += ['{name}={value}'.format(name=name, value=value)]
    self._commandToRun = env + self._commandToRun

  def _createRunScript(self):
    """Helper to create a run script when configured to work around issues with
    command lines being too long"""
    root, ext = os.path.splitext(self._logFilename)
    extensionCount = re.search(r'([0-9]*)$', ext).group(0)
    filename = '{root}.run{count}'.format(root=root, count=extensionCount)
    logging.debug('Creating run script with filename {filename}'.format(filename=filename))
    runFile = open(filename, 'w')
    runFile.write("#!/bin/sh\n")
    if self._config.get('copy_environment', False):
      for name, value in self._getEnvironmentToCopy().items():
        runFile.write("export {name}={value}\n".format(name=DistManager.shlexQuote(name), value=DistManager.shlexQuote(value)))
    runFile.write("exec {command}\n".format(command=DistManager.shlexJoin(self._commandToRun)))
    runFile.close()
    status = os.stat(filename)
    os.chmod(filename, status.st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    self._commandToRun = [os.path.abspath(filename)]

  def _attachSignalHandlers(self):
    """Attach signal handlers for INT, HUP, ALRM, TERM, USR1, USR2 so we can
    pass them through to the distributed process"""
    self._previousSignalHandlers = {}
    for sig in [signal.SIGINT, signal.SIGHUP, signal.SIGALRM, signal.SIGTERM, signal.SIGUSR1, signal.SIGUSR2]:
      self._previousSignalHandlers[sig] = signal.signal(sig, self._signalHandler)

  def _detachSignalHandlers(self):
    """Detach signal handlers so that ctrl+C can be used to kill long-running
    reporting commands, etc after the distributed process has exited"""
    for sig, handler in self._previousSignalHandlers.items():
      signal.signal(sig, handler)

  def _signalHandler(self, signum, frame):
    """Handle signals by queuing them for the monitoring thread to pass to the
    distribution method"""
    logging.debug('Received signal {signal}'.format(signal=signum))
    with self.pendingSignalsLock:
      self.pendingSignals.append(signum)
      self.messagePending.set()

  def _finishedCallback(self):
    """Callback passed to the constructor of distribution methods for notifying
    that the distributed process has exited (either success or failure)"""
    logging.debug('Received process finished callback')
    self.processFinished.set()
    self.messagePending.set()

  def _startProcess(self):
    """Construct the distribution method class and call the start function to
    begin the distributed process"""
    methodCls = self.getMethod(self._config['dist'])
    logging.info('Host: {host}'.format(host=socket.gethostname()))
    logging.info('Method: {method}'.format(method=self._config['dist']))
    logging.info('Command: {command}'.format(command=DistManager.shlexJoin(self._commandToRun)))
    logging.info('Process starting')
    if self._config['interactive']:
      # Disable info logging to stdout as the tool session will be using stdout
      self._consoleLogger.setLevel(logging.WARNING)
    self._dist = methodCls(config=self._config, finished=self._finishedCallback)
    self._dist.start(argv=self._commandToRun)

  def _createMonitorThread(self):
    """Create a thread to poll the status of the process and return that thread
    (not yet started)"""
    thread = threading.Thread(target=self._monitorProcess, name='DistManagerMonitorThread', kwargs={'pollInitial': self._config['status_timeout_initial'], 'pollIncrement': self._config['status_timeout_increment'], 'pollLimit': self._config['status_timeout_limit']})
    # Use old setDaemon setter to support python 3.2
    thread.setDaemon(True)
    return thread

  def _forceKill(self):
    """Send a KILL signal to the distributed process"""
    logging.debug('Force kill timeout fired, sending SIGKILL')
    with self.pendingSignalsLock:
      self.pendingSignals.append(signal.SIGKILL)
      self.messagePending.set()

  def _monitorProcess(self, pollInitial=10, pollIncrement=10, pollLimit=180):
    """Poll the distribution method checking status, along with passing on
    queued signals and responding to the finished callback; will block until the
    distributed process has exited (either success or failure)"""
    pollTime = pollInitial
    try:
      while True:
        # Wake up at every few seconds to report status
        self.messagePending.wait(timeout=pollTime)
        if pollTime < pollLimit:
          pollTime += pollIncrement
        logging.debug('Event loop woke up')
        self.messagePending.clear()
        if self.processFinished.is_set():
          logging.debug('processFinished is set, ending monitor')
          return
        with self.pendingSignalsLock:
          if len(self.pendingSignals) > 0:
            # Reset back to pollInitial so we are more responsive to the
            # "result" of signals (e.g. process exiting)
            pollTime = pollInitial
            while len(self.pendingSignals) > 0:
              signum = self.pendingSignals.pop(0)
              logging.info('Dispatching signal {signal} to process'.format(signal=signum))
              self._dist.signal(signum)
              if self._config['force_kill_after_interrupt'] and self._killTimer is None and self._config['force_kill_timeout'] >= 0 and signum in [signal.SIGINT, signal.SIGTERM]:
                self._killTimer = threading.Timer(self._config['force_kill_timeout'], self._forceKill)
                self._killTimer.start()
            continue
        if self._dist is None:
          logging.info('id=None, state=STARTING, runtime=None, memory=None')
        else:
          status = self._dist.getStatus()
          if status is None:
            logging.info('id=None, state=UNKNOWN, runtime=None, memory=None')
          else:
            runtime = None
            if status.get('runtime_s', None) is not None:
              h, rem = divmod(status['runtime_s'], 3600)
              m, s = divmod(rem, 60)
              runtime = '{H:0>2d}:{M:0>2d}:{S:0>2d}'.format(H=int(h), M=int(m), S=int(s))
            memory = None
            if status.get('memory_mb', None) is not None:
              memory = '{memory:d}MB'.format(memory=status['memory_mb'])
            logging.info('id={pid}, state={state}, runtime={runtime}, memory={memory}'.format(pid=status.get('id', None), state=status.get('state', None), runtime=runtime, memory=memory))
    except Exception as error:
      # Make sure we log exceptions in the monitor thread; no need to reraise
      # here as this handler will call sys.__excepthook__
      self._logException(*sys.exc_info())

  def _reportResult(self):
    """Fetch the result from the distribution class and log the results (and
    email reports if configured)"""
    if self._config['interactive']:
      # Re-enable logging on stdout
      if self._config['debug']:
        self._consoleLogger.setLevel(logging.DEBUG)
      else:
        self._consoleLogger.setLevel(logging.INFO)
    result = self._dist.getResult(forceFullReport=self._config['debug'], generateFullReportOnError=(self._config['email_addr'] is not None))
    if result is None:
      logging.info('getResult returned None, exiting in error due to unknown state')
      return 1
    else:
      if result.get('stderr', None) is not None and result['stderr'].strip() != '':
        logging.warning('Process STDERR: {stderr}'.format(stderr=result['stderr'].strip()))
      if result.get('report', None) is not None and result['report'].strip() != '':
        logging.debug('Report: {report}'.format(report=result['report'].strip()))
        if self._config['email_addr'] is not None:
          command = ['mail', '-s', 'dist.py report for {taskName}'.format(taskName=self._config['task_name']), self._config['email_addr']]
          logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command)))
          # We need to open /dev/null instead of using subprocess.DEVNULL to
          # support Python 3.2
          with open(os.devnull, 'w') as devnull:
            mail = subprocess.Popen(command, stdout=devnull, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
            _, errs = mail.communicate(result['report'].encode('utf-8'))
          if errs is not None:
            err = errs.decode('utf-8').strip()
            if err is not None and err != '':
              logging.warning('mail STDERR: ' + err.strip())
      logging.info('Process exited with status {code}'.format(code=result.get('status', None)))
      logging.info('Exiting with status {code}'.format(code=result.get('status', None)))
      return result.get('status', None)

  def _uniqueFilename(self, basename):
    """Helper to generate a innovus-stylus unique filename for log filenames"""
    i = 0
    unique = basename
    while os.path.exists(unique):
      i += 1
      unique = basename + str(i)
    return unique

  def _parseTclList(self, tcl):
    """Helper to parse a tcl list into a python list"""
    output = []
    matchingCharType = None
    depth = 0
    startPosition = 0
    escaped = False
    for i in range(len(tcl)):
      character = tcl[i]
      if matchingCharType == '"':
        if not escaped:
          if character == '"':
            output.append(tcl[startPosition:i])
            matchingCharType = None
      elif matchingCharType == '{':
        if not escaped:
          if character == '}':
            if depth == 0:
              output.append(tcl[startPosition:i])
              matchingCharType = None
            else:
              depth -= 1
          elif character == '{':
            depth += 1
      elif matchingCharType == ' ':
        if not escaped:
          if character == ' ':
            output.append(tcl[startPosition:i])
            matchingCharType = None
      else:
        if character == ' ':
          pass
        elif character == '"' or character == '{':
          depth = 0
          matchingCharType = character
          startPosition = i + 1
        else:
          depth = 0
          matchingCharType = ' '
          startPosition = i
      if character == '\\':
        escaped = not escaped
      else:
        escaped = False
    if matchingCharType == ' ':
      output.append(tcl[startPosition:])
      matchingCharType = None
    return output

  @staticmethod
  def shlexQuote(s):
    """Return a shell-escaped version of the string *s*. Polyfill for python
    3.3 shlex.quote"""
    if not s:
        return "''"
    if re.search(r'[^\w@%+=:,./-]', s) is None:
        return s
    # use single quotes, and put single quotes into double quotes
    # the string $'b is then quoted as '$'"'"'b'
    return "'" + s.replace("'", "'\"'\"'") + "'"

  @staticmethod
  def shlexJoin(split_command):
    """Return a shell-escaped string from *split_command*. Polyfill for python
    3.8 shlex.join"""
    return ' '.join(DistManager.shlexQuote(arg) for arg in split_command)

class DistBase(object):
  """Base `virtual` class for distribution methods, not intended to be used
  directly but instead inherited from"""
  config = DefaultConfig

  @classmethod
  def calculateConfig(cls, defaultConfig, config):
    """Take the FlowConfig and merge with the config specific for this
    distribution mechanism"""
    distConfig = {}
    for key in dir(cls.config):
      if not key.startswith('__') and not callable(getattr(cls.config, key)):
        distConfig[key] = getattr(cls.config, key)
    newConfig = {}
    # Let the flow config overwrite dist config
    newConfig.update(defaultConfig)
    newConfig.update(distConfig)
    newConfig.update(config)
    return newConfig

  def __init__(self, config={}, finished=None):
    """Initialize the distribution method, but don't do anything yet (start will
    be called later). config is the finalized and merged config, finished is a
    callback function to report that the process has completed (either success
    or failure)"""
    self._config = config
    self._finished = finished

  def _createNewProcessGroup(self):
    """Helper to alter the process group ID so that we don't automatically
    receive Ctrl-C in the child process, we can then pass it on manually;
    intended to be used as a preexec_fn to subprocess.Popen. This is useful in
    farm distribution methods when handling Ctrl+C so we can instead call a kill
    command"""
    pid = os.getpid()
    os.setpgid(pid, 0)

  def _exeInSameDir(self, base, exe):
    """Helper to take a list of arguments for an executable (assume the last
    list item is the executable name, e.g. python3.2 /path/to/dist.py would pick
    dist.py), take the `dirname` and put a different executable name on the end
    in the same path. This is useful for distribution methods which use a series
    of commands in the same directory, e.g. bsub, bjobs, bkill, bhist"""
    dirname = os.path.dirname(base[-1])
    if dirname != '':
      exe = os.path.join(dirname, exe)
    return base[:-1] + [exe]

  def start(self, argv):
    """Start or submit the process, argv is an array of the command needing to
    be run"""
    raise NotImplementedError()

  def _finish(self):
    """Helper to make it simpler to call the finished callback"""
    if self._finished is not None:
      self._finished()

  def signal(self, signum):
    """Send a signal to the child process"""
    raise NotImplementedError()

  def getStatus(self):
    """Get the status of the process. Will be called periodically (can be called
    before start). Returns either None, or an object {'id': <any>, 'state':
    <str>, 'runtime_s': <int>, 'memory_mb': <int>}, object values can also be
    None"""
    raise NotImplementedError()

  def getResult(self, forceFullReport=False, generateFullReportOnError=False):
    """Get the result of the process. Returns either None or an object
    {'status': <int>, 'stderr': <str>, 'report': <str>}, object values can also
    be None"""
    raise NotImplementedError()

class DistLocal(DistBase):
  """Distribution method to run the process on the local machine"""
  config = LocalDistConfig

  def __init__(self, config={}, finished=None):
    """Initialize the distribution method, but don't do anything yet (start will
    be called later). config is the finalized and merged config, finished is a
    callback function to report that the process has completed (either success
    or failure)"""
    super().__init__(config=config, finished=finished)
    self._failedStatusCount = 0
    self._errs = None
    self._returnCode = None
    self._process = None

  def start(self, argv):
    """Start or submit the process, argv is an array of the command needing to
    be run"""
    logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(argv)))
    if self._config['interactive']:
      # Don't change the process group as we would then need to mess around with
      # tcsetpgrp and potentially sending a CONT signal to make stdin work
      self._process = subprocess.Popen(argv, stdout=sys.stdout, stderr=sys.stderr, stdin=sys.stdin)
      _, errs = self._process.communicate()
    elif self._config['capture_stdout']:
      self._process = subprocess.Popen(argv, preexec_fn=self._createNewProcessGroup, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      outs, errs = self._process.communicate()
      if outs is not None:
        out = outs.decode('utf-8').strip()
        if out != '':
          logging.info('Process STDOUT: {stdout}'.format(stdout=out))
    else:
      with open(os.devnull, 'w') as devnull:
        self._process = subprocess.Popen(argv, preexec_fn=self._createNewProcessGroup, stdout=devnull, stderr=subprocess.PIPE)
        _, errs = self._process.communicate()
    if errs is not None:
      self._errs = errs.decode('utf-8')
    self._returnCode = self._process.poll()
    self._finish()

  def signal(self, signum):
    """Send a signal to the child process"""
    if self._process is not None and self._process.poll() is None:
      # Don't send the signal if interactive, we didn't change the process group
      # so it will naturally already receive the signal. KILL is synthetic and
      # not from the shell so we need to manually send it through
      if not self._config['interactive'] or signum == signal.SIGKILL:
        self._process.send_signal(signum)

  def getStatus(self):
    """Get the status of the process. Will be called periodically (can be called
    before start). Returns either None, or an object {'id': <any>, 'state':
    <str>, 'runtime_s': <int>, 'memory_mb': <int>}, object values can also be
    None"""
    if self._process is not None:
      pid = self._process.pid
      startTime = int(os.path.getctime('/proc/{pid}/stat'.format(pid=pid)))
      runtime_s = int(time.time()) - startTime
      memory_mb = None
      with open('/proc/{pid}/status'.format(pid=pid)) as f:
        getVmData = re.compile(r'^VmData:\s+([0-9]+) kB', re.ASCII).search
        for line in f:
          usage = getVmData(line.strip())
          if usage:
            memory_mb = int(int(usage.group(1)) / 1024)
            break
      self._failedStatusCount = 0
      return {
        'id': pid,
        'state': 'RUN',
        'runtime_s': runtime_s,
        'memory_mb': memory_mb
      }
    else:
      self._failedStatusCount += 1
      if self._failedStatusCount > 3:
        self._finish()
      return None

  def getResult(self, forceFullReport=False, generateFullReportOnError=False):
    """Get the result of the process. Returns either None or an object
    {'status': <int>, 'stderr': <str>, 'report': <str>}, object values can also
    be None"""
    if self._process is not None and self._process.poll() is not None:
      return {
        'status': self._returnCode,
        'stderr': self._errs,
        'report': None
      }
    else:
      return None
DistManager.registerMethod('local', DistLocal)

class DistSsh(DistBase):
  """Distribution method to run the process on a remote ssh connection"""
  config = SshDistConfig

  @classmethod
  def calculateConfig(cls, defaultConfig, config):
    """Take the FlowConfig and merge with the config specific for this
    distribution mechanism"""
    newConfig = super().calculateConfig(defaultConfig, config)
    # Allow ssh_exe and ssh_host to be a list of arguments, or a shell-quoted
    # string of arguments
    if isinstance(newConfig.get('ssh_exe', 'ssh'), str):
      newConfig['ssh_exe'] = shlex.split(newConfig.get('ssh_exe', 'ssh'))
    if isinstance(newConfig.get('ssh_host', 'localhost'), str):
      newConfig['ssh_host'] = shlex.split(newConfig.get('ssh_host', 'localhost'))
    return newConfig

  def __init__(self, config={}, finished=None):
    """Initialize the distribution method, but don't do anything yet (start will
    be called later). config is the finalized and merged config, finished is a
    callback function to report that the process has completed (either success
    or failure)"""
    super().__init__(config=config, finished=finished)
    self._failedStatusCount = 0
    self._errs = None
    self._returnCode = None
    self._process = None

  def start(self, argv):
    """Start or submit the process, argv is an array of the command needing to
    be run"""
    command = [] + self._config['ssh_exe'] + self._config['ssh_host']
    command += [DistManager.shlexJoin(["cd", os.getcwd()]) + ";" + DistManager.shlexJoin(argv)]
    logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command)))
    if self._config['interactive']:
      self._process = subprocess.Popen(command, stdout=sys.stdout, stderr=sys.stderr, stdin=sys.stdin)
      _, errs = self._process.communicate()
    else:
      with open(os.devnull, 'w') as devnull:
        self._process = subprocess.Popen(command, stdout=devnull, stderr=subprocess.PIPE)
        _, errs = self._process.communicate()
    if errs is not None:
      self._errs = errs.decode('utf-8')
    self._returnCode = self._process.poll()
    self._finish()

  def signal(self, signum):
    """Send a signal to the child process"""
    # No need to manually pass on signals, we have not changed process group.
    # This sends the signal to ssh, not to the tool session on the remote host
    # as we do not know the PID on the remote host to ssh 'kill <pid>'.
    if signum == signal.SIGKILL:
      self._process.send_signal(signum)

  def getStatus(self):
    """Get the status of the process. Will be called periodically (can be called
    before start). Returns either None, or an object {'id': <any>, 'state':
    <str>, 'runtime_s': <int>, 'memory_mb': <int>}, object values can also be
    None"""
    if self._process is not None:
      pid = self._process.pid
      startTime = int(os.path.getctime('/proc/{pid}/stat'.format(pid=pid)))
      runtime_s = int(time.time()) - startTime
      self._failedStatusCount = 0
      return {
        'id': pid,
        'state': 'RUN',
        'runtime_s': runtime_s,
        'memory_mb': None
      }
    else:
      self._failedStatusCount += 1
      if self._failedStatusCount > 3:
        self._finish()
      return None

  def getResult(self, forceFullReport=False, generateFullReportOnError=False):
    """Get the result of the process. Returns either None or an object
    {'status': <int>, 'stderr': <str>, 'report': <str>}, object values can also
    be None"""
    if self._process is not None and self._process.poll() is not None:
      return {
        'status': self._returnCode,
        'stderr': self._errs,
        'report': None
      }
    else:
      return None
DistManager.registerMethod('ssh', DistSsh)

class DistLsf(DistBase):
  """Distribution method to run the process on a LSF farm"""
  config = LsfDistConfig

  @classmethod
  def calculateConfig(cls, defaultConfig, config):
    """Take the FlowConfig and merge with the config specific for this
    distribution mechanism"""
    newConfig = super().calculateConfig(defaultConfig, config)
    # Allow bsub_exe, bsub_args and queue to be a list of arguments, or a
    # shell-quoted string of arguments
    if isinstance(newConfig.get('bsub_exe', 'bsub'), str):
      newConfig['bsub_exe'] = shlex.split(newConfig.get('bsub_exe', 'bsub'))
    if isinstance(newConfig.get('bsub_args', ''), str):
      newConfig['bsub_args'] = shlex.split(newConfig.get('bsub_args', ''))
    if isinstance(newConfig.get('queue', ''), str):
      newConfig['queue'] = shlex.split(newConfig.get('queue', ''))
    return newConfig

  def __init__(self, config={}, finished=None):
    """Initialize the distribution method, but don't do anything yet (start will
    be called later). config is the finalized and merged config, finished is a
    callback function to report that the process has completed (either success
    or failure)"""
    super().__init__(config=config, finished=finished)
    self._failedStatusCount = 0
    self._errs = None
    self._returnCode = None
    self._jobid = None
    self._submitting = False
    self._bsubProcess = None

  def start(self, argv):
    """Start or submit the process, argv is an array of the command needing to
    be run"""
    self._submitting = True
    command = [] + self._config['bsub_exe'] + self._config['bsub_args'] + ['-q'] + self._config['queue']
    logPaths = [handler.baseFilename for handler in logging.getLogger("").handlers if isinstance(handler, logging.FileHandler)]
    logPath = 'dist'
    if len(logPaths) > 0:
      logPath = logPaths[0]
    command += ['-n', str(self._config.get('threads', 1)), '-J', self._config['task_name']]
    if 'memory_mb' in self._config:
      command += ['-R', '{config} rusage[mem={mem}]'.format(config=self._config['bsub_resource'], mem=self._config['memory_mb']).strip()]
    else:
      command += ['-R', self._config.get('bsub_resource', '').strip()]
    if self._config['interactive']:
      command += ['-Is']
      logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command + argv)))
      self._bsubProcess = subprocess.Popen(command + argv, stdout=sys.stdout, stderr=sys.stderr, stdin=sys.stdin)
    else:
      command += ['-eo', '{path}.%J.stderr'.format(path=logPath)]
      if self._config['debug']:
        command += ['-o', '{path}.%J.lsf'.format(path=logPath)]
      else:
        command += ['-o', '/dev/null']
      logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command + argv)))
      self._bsubProcess = subprocess.Popen(command + argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    outs, errs = self._bsubProcess.communicate()
    self._submitting = False
    returnCode = self._bsubProcess.poll()
    self._bsubProcess = None
    logging.debug('bsub return code is {code}'.format(code=returnCode))
    if errs is not None:
      err = errs.decode('utf-8').strip()
      if err != '':
        logging.warning('bsub STDERR: ' + err.strip())
    if returnCode == 0:
      if self._config['interactive']:
        self._returnCode = returnCode
        self._finish()
      else:
        if outs is None:
          raise RuntimeError('bsub did not produce any output, cannot work out submitted job id.')
        out = outs.decode('utf-8')
        reg_result = re.search(r'.*Job <([0-9]+)> is submitted to queue.*', out)
        if not reg_result:
          if out.strip() != '':
            logging.warning('bsub STDOUT: {out}'.format(out=out))
          raise RuntimeError('could not match submitted job id from bsub output.')
        self._jobid = reg_result.group(1).strip()
        logging.debug('Matched bsub job id: {jobid}'.format(jobid=self._jobid))
    else:
      self._returnCode = returnCode
      if self._config['interactive']:
        self._finish()
      else:
        if outs is not None:
          out = outs.decode('utf-8')
          reg_result = re.search(r'.*Job <([0-9]+)> is submitted to queue.*', out)
          if not reg_result:
            if out.strip() != '':
              logging.warning('bsub STDOUT: {out}'.format(out=out))
            raise RuntimeError('could not match submitted job id from bsub output.')
          self._jobid = reg_result.group(1).strip()
        self._finish()

  def signal(self, signum):
    """Send a signal to the child process"""
    if self._jobid is not None:
      bkillExe = self._exeInSameDir(self._config['bsub_exe'], 'bkill')
      command = bkillExe + ['-s', str(signum), '-q'] + self._config['queue'] + [self._jobid]
      logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command)))
      with open(os.devnull, 'w') as devnull:
        process = subprocess.Popen(command, stdout=devnull, stderr=subprocess.PIPE)
        _, errs = process.communicate()
      if errs is not None:
        err = errs.decode('utf-8').strip()
        if err is not None and err != '':
          logging.warning('bkill STDERR: ' + err.strip())
    elif self._bsubProcess is not None:
      if not self._config['interactive'] or signum == signal.SIGKILL:
        self._bsubProcess.send_signal(signum)

  def getStatus(self):
    """Get the status of the process. Will be called periodically (can be called
    before start). Returns either None, or an object {'id': <any>, 'state':
    <str>, 'runtime_s': <int>, 'memory_mb': <int>}, object values can also be
    None"""
    if self._jobid is not None:
      state = 'UNKNOWN'
      runtime_s = None
      memory_mb = None
      bjobsExe = self._exeInSameDir(self._config['bsub_exe'], 'bjobs')
      command = bjobsExe + ['-o', 'id stat run_time mem exit_code', '-json', '-q'] + self._config['queue'] + [self._jobid]
      logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command)))
      process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      outs, errs = process.communicate()
      if errs is not None:
        err = errs.decode('utf-8').strip()
        if err != '':
          logging.warning('bjobs STDERR: ' + err.strip())
      if outs is not None:
        try:
          out = json.loads(outs.decode('utf-8'))
        except JSONDecodeError as error:
          logging.warning('bjobs json decode error: {msg}\n{out}'.format(msg=error.msg, out=outs.decode('utf-8')))
          self._failedStatusCount += 1
          if self._failedStatusCount > 3:
            self._finish()
            raise
          else:
            return None
        else:
          try:
            data = out['RECORDS'][0]
            state = data['STAT']
            runtime = data.get('RUN_TIME', '').split()
            if len(runtime) > 0 and runtime[0].isnumeric():
              runtime_s = int(runtime[0])
            memory = data.get('MEM', '').split()
            if len(memory) > 0 and memory[0].isnumeric():
              memory_mb = int(memory[0])
            exit_code = data.get('EXIT_CODE', '')
            if exit_code != '':
              self._returnCode = int(exit_code)
          except IndexError as error:
            logging.warning('bjobs structure does not match expectations: {structure}'.format(structure=json.dumps(out)))
            self._failedStatusCount += 1
            if self._failedStatusCount > 3:
              self._finish()
              raise
            else:
              return None
          except KeyError as error:
            logging.warning('bjobs structure does not match expectations: {structure}'.format(structure=json.dumps(out)))
            self._failedStatusCount += 1
            if self._failedStatusCount > 3:
              self._finish()
              raise
            else:
              return None
        if state in ['UNKNWN', 'EXIT', 'DONE']:
          if self._returnCode is None:
            # Default an exit status if not set
            if state in ['UNKNWN', 'EXIT']:
              self._returnCode = 1
            else:
              self._returnCode = 0
          self._finish()
        self._failedStatusCount = 0
      else:
        self._failedStatusCount += 1
        if self._failedStatusCount > 3:
          self._finish()
      return {
        'id': self._jobid,
        'state': state,
        'runtime_s': runtime_s,
        'memory_mb': memory_mb
      }
    elif self._submitting:
      self._failedStatusCount = 0
      return {
        'id': None,
        'state': 'SUBMITTING',
        'runtime_s': None,
        'memory_mb': None
      }
    else:
      self._failedStatusCount += 1
      if self._failedStatusCount > 3:
        self._finish()
      return None

  def getResult(self, forceFullReport=False, generateFullReportOnError=False):
    """Get the result of the process. Returns either None or an object
    {'status': <int>, 'stderr': <str>, 'report': <str>}, object values can also
    be None"""
    if self._jobid is not None or self._returnCode is not None:
      report = None
      if self._jobid is not None and (forceFullReport or (generateFullReportOnError and self._returnCode is not None and self._returnCode != 0)):
        bhistExe = self._exeInSameDir(self._config['bsub_exe'], 'bhist')
        command = bhistExe + ['-q'] + self._config['queue'] + ['-l', '-UF', self._jobid]
        logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command)))
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        outs, errs = process.communicate()
        if errs is not None:
          err = errs.decode('utf-8').strip()
          if err != '':
            logging.warning('bhist STDERR: ' + err.strip())
        if outs is not None:
          report = outs.decode('utf-8').strip()
      return {
        'status': self._returnCode,
        'stderr': self._errs,
        'report': report
      }
    else:
      return None
DistManager.registerMethod('lsf', DistLsf)

class DistSge(DistBase):
  """Distribution method to run the process on a SGE farm"""
  config = SgeDistConfig

  @classmethod
  def calculateConfig(cls, defaultConfig, config):
    """Take the FlowConfig and merge with the config specific for this
    distribution mechanism"""
    newConfig = super().calculateConfig(defaultConfig, config)
    # Allow qsub_exe, qsub_args and queue to be a list of arguments, or a
    # shell-quoted string of arguments
    if isinstance(newConfig.get('qsub_exe', 'qsub'), str):
      newConfig['qsub_exe'] = shlex.split(newConfig.get('qsub_exe', 'qsub'))
    if isinstance(newConfig.get('qsub_args', ''), str):
      newConfig['qsub_args'] = shlex.split(newConfig.get('qsub_args', ''))
    if isinstance(newConfig.get('queue', ''), str):
      newConfig['queue'] = shlex.split(newConfig.get('queue', ''))
    return newConfig

  def __init__(self, config={}, finished=None):
    """Initialize the distribution method, but don't do anything yet (start will
    be called later). config is the finalized and merged config, finished is a
    callback function to report that the process has completed (either success
    or failure)"""
    super().__init__(config=config, finished=finished)
    self._failedStatusCount = 0
    self._errs = None
    self._returnCode = None
    self._jobid = None
    self._submitting = False

  def start(self, argv):
    """Start or submit the process, argv is an array of the command needing to
    be run"""
    self._submitting = True
    if self._config['interactive']:
      command = self._exeInSameDir(self._config['qsub_exe'], 'qrsh')
    else:
      command = [] + self._config['qsub_exe']
    command += self._config['qsub_args'] + ['-q'] + self._config['queue']
    command += ['-V', '-N', self._config['task_name'].replace('@', '-').replace('/', '-')]
    logPaths = [handler.baseFilename for handler in logging.getLogger("").handlers if isinstance(handler, logging.FileHandler)]
    logPath = 'dist'
    if len(logPaths) > 0:
      logPath = logPaths[0]
    if 'memory_mb' in self._config:
      command += ['-l', 'mem={mem}M'.format(mem=self._config['memory_mb']).strip()]
    if self._config['interactive']:
      logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command + argv)))
      process = subprocess.Popen(command + argv, stdout=sys.stdout, stderr=sys.stderr, stdin=sys.stdin)
    else:
      command += ['-e', '{path}.$JOB_ID.stderr'.format(path=logPath)]
      logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command + argv)))
      process = subprocess.Popen(command + argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    outs, errs = process.communicate()
    self._submitting = False
    returnCode = process.poll()
    logging.debug('qsub return code is {code}'.format(code=returnCode))
    if errs is not None:
      err = errs.decode('utf-8').strip()
      if err != '':
        logging.warning('qsub STDERR: ' + err.strip())
    if returnCode == 0:
      if self._config['interactive']:
        self._returnCode = returnCode
        self._finish()
      else:
        out = outs.decode('utf-8')
        # If qsub prints the job ID with a message, this will need updating,
        # e.g. r'.*Your job ([0-9]+).* has been submitted.*'
        reg_result = re.search(r'(.*)', out)
        if not reg_result:
          if out.strip() != '':
            logging.warning('bsub STDOUT: {out}'.format(out=out))
          raise RuntimeError('could not match submitted job id from bsub output.')
        self._jobid = reg_result.group(1).strip()
        logging.debug('Matched qsub job id: {jobid}'.format(jobid=self._jobid))
    else:
      self._returnCode = returnCode
      if self._config['interactive']:
        self._finish()
      else:
        if outs is not None:
          out = outs.decode('utf-8').strip()
          if out == '':
            raise RuntimeError('could not match submitted job id from qsub output.')
          self._jobid = out
        self._finish()

  def signal(self, signum):
    """Send a signal to the child process"""
    if self._jobid is not None:
      # Do not SIGKILL the job for USR1 or USR2 signals
      if signum not in [signal.SIGUSR1, signal.SIGUSR2]:
        qdelExe = self._exeInSameDir(self._config['qsub_exe'], 'qdel')
        command = qdelExe + [self._jobid]
        logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command)))
        with open(os.devnull, 'w') as devnull:
          process = subprocess.Popen(command, stdout=devnull, stderr=subprocess.PIPE)
          _, errs = process.communicate()
        if errs is not None:
          err = errs.decode('utf-8').strip()
          if err is not None and err != '':
            logging.warning('qdel STDERR: ' + err.strip())

  def getStatus(self):
    """Get the status of the process. Will be called periodically (can be called
    before start). Returns either None, or an object {'id': <any>, 'state':
    <str>, 'runtime_s': <int>, 'memory_mb': <int>}, object values can also be
    None"""
    if self._jobid is not None:
      state = 'UNKNOWN'
      runtime_s = None
      memory_mb = None
      qstatExe = self._exeInSameDir(self._config['qsub_exe'], 'qstat')
      command = qstatExe + ['-u', getpass.getuser()]
      logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command)))
      process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      outs, errs = process.communicate()
      if errs is not None:
        err = errs.decode('utf-8').strip()
        if err != '':
          logging.warning('qstat STDERR: ' + err.strip())
      if outs is not None:
        out = outs.decode('utf-8').splitlines()
        if any(self._jobid in line for line in out):
          for line in out[2:]:
            line = line.split()
            if len(line) >= 8 and line[0] == self._jobid:
              # This may need changing based on where the state appears in qstat
              # output, counting from the left, the first item is 0, second is
              # 1, etc
              state = line[9]
              # This may need updating based on the date format that qstat is
              # showing. Examples:
              # 31/12/99 23:59:59 = '%d/%m/%y %H:%M:%S'
              # 12/31/1999 23:59:59 = '%m/%d/%Y %H:%M:%S'
              starttime = datetime.strptime(' '.join(line[5:7]), '%d/%m/%y %H:%M:%S')
              runtime_s = (datetime.now() - starttime).total_seconds()
              break
          self._failedStatusCount = 0
        else:
          self._failedStatusCount += 1
          if self._failedStatusCount > 3:
            self._finish()
        if state in ['Eqw', 'Ehqw', 'EhRqw', 'dr', 'dt', 'dRr', 'dRt', 'ds', 'dS', 'dT', 'dRs', 'dRS', 'dRT']:
          if self._returnCode is None:
            # Default an exit status if not set
            self._returnCode = 1
          self._finish()
        if state in ['s', 'ts', 'S', 'tS', 'T', 'tT', 'Rs', 'Rts', 'RS', 'RtS', 'RT', 'RtT']:
          if self._returnCode is None:
            # Default an exit status if not set
            self._returnCode = 0
          self._finish()
      else:
        self._failedStatusCount += 1
        if self._failedStatusCount > 3:
          self._finish()
      return {
        'id': self._jobid,
        'state': state,
        'runtime_s': runtime_s,
        'memory_mb': memory_mb
      }
    elif self._submitting:
      self._failedStatusCount = 0
      return {
        'id': None,
        'state': 'SUBMITTING',
        'runtime_s': None,
        'memory_mb': None
      }
    else:
      self._failedStatusCount += 1
      if self._failedStatusCount > 3:
        self._finish()
      return None

  def getResult(self, forceFullReport=False, generateFullReportOnError=False):
    """Get the result of the process. Returns either None or an object
    {'status': <int>, 'stderr': <str>, 'report': <str>}, object values can also
    be None"""
    if self._jobid is not None or self._returnCode is not None:
      report = None
      return {
        'status': self._returnCode,
        'stderr': self._errs,
        'report': None
      }
    else:
      return None
DistManager.registerMethod('sge', DistSge)

class DistNb(DistBase):
  """Distribution method to run the process on a NetBatch farm"""
  config = NbDistConfig

  @classmethod
  def calculateConfig(cls, defaultConfig, config):
    """Take the FlowConfig and merge with the config specific for this
    distribution mechanism"""
    newConfig = super().calculateConfig(defaultConfig, config)
    # Allow nb_exe, nb_run_args and target to be a list of arguments, or a
    # shell-quoted string of arguments
    if isinstance(newConfig.get('nb_exe', 'nb'), str):
      newConfig['nb_exe'] = shlex.split(newConfig.get('nb_exe', 'nb'))
    if isinstance(newConfig.get('nb_run_args', ''), str):
      newConfig['nb_run_args'] = shlex.split(newConfig.get('nb_run_args', ''))
    if isinstance(newConfig.get('target', ''), str):
      newConfig['target'] = shlex.split(newConfig.get('target', ''))
    return newConfig

  def __init__(self, config={}, finished=None):
    """Initialize the distribution method, but don't do anything yet (start will
    be called later). config is the finalized and merged config, finished is a
    callback function to report that the process has completed (either success
    or failure)"""
    super().__init__(config=config, finished=finished)
    self._failedStatusCount = 0
    self._errs = None
    self._returnCode = None
    self._jobid = None
    self._submitting = False

  def start(self, argv):
    """Start or submit the process, argv is an array of the command needing to
    be run"""
    self._submitting = True
    command = [] + self._config['nb_exe'] + ['run', '--task', self._config['task_name']]
    resource_string = self._config['nb_run_resource']
    if 'memory_mb' in self._config:
      resource_string += '&&{mem}G'.format(mem=int(self._config['memory_mb']/1024))
    if 'threads' in self._config:
      resource_string += '&&{threads}C'.format(threads=self._config['threads'])
    command += self._config['nb_run_args'] + ['--target'] + self._config['target']
    logPaths = [handler.baseFilename for handler in logging.getLogger("").handlers if isinstance(handler, logging.FileHandler)]
    logPath = 'dist'
    if len(logPaths) > 0:
      logPath = logPaths[0]
    if self._config['interactive']:
      command += ['--mode interactive']
      logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command + argv)))
      process = subprocess.Popen(command + argv, stdout=sys.stdout, stderr=sys.stderr, stdin=sys.stdin)
    else:
      command += ['--log-file', '{path}.nb'.format(path=logPath)]
      logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command + argv)))
      process = subprocess.Popen(command + argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    outs, errs = process.communicate()
    self._submitting = False
    returnCode = process.poll()
    logging.debug('nb run return code is {code}'.format(code=returnCode))
    if errs is not None:
      err = errs.decode('utf-8').strip()
      if err != '':
        logging.warning('nb run STDERR: ' + err.strip())
    if returnCode == 0:
      if self._config['interactive']:
        self._returnCode = returnCode
        self._finish()
      else:
        if outs is None:
          raise RuntimeError('nb run did not produce any output, cannot work out submitted job id.')
        out = outs.decode('utf-8')
        reg_result = re.search(r'.*Your job has been queued \(JobID ([0-9]+).*', out)
        if not reg_result:
          if out.strip() != '':
            logging.warning('nb run STDOUT: {out}'.format(out=out))
          raise RuntimeError('could not match submitted job id from nb run output.')
        self._jobid = reg_result.group(1).strip()
        logging.debug('Matched nb run job id: {jobid}'.format(jobid=self._jobid))
    else:
      self._returnCode = returnCode
      if self._config['interactive']:
        self._finish()
      else:
        if outs is not None:
          out = outs.decode('utf-8')
          reg_result = re.search(r'.*Your job has been queued \(JobID ([0-9]+).*', out)
          if not reg_result:
            if out.strip() != '':
              logging.warning('nb run STDOUT: {out}'.format(out=out))
            raise RuntimeError('could not match submitted job id from nb run output.')
          self._jobid = reg_result.group(1).strip()
        self._finish()

  def signal(self, signum):
    """Send a signal to the child process"""
    if self._jobid is not None:
      # Do not SIGKILL the job for USR1 or USR2 signals
      if signum not in [signal.SIGUSR1, signal.SIGUSR2]:
        command = [] + self._config['nb_exe'] + ['remove', '--target'] + self._config['target'] + [self._jobid]
        logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command)))
        with open(os.devnull, 'w') as devnull:
          process = subprocess.Popen(command, stdout=devnull, stderr=subprocess.PIPE)
          _, errs = process.communicate()
        if errs is not None:
          err = errs.decode('utf-8').strip()
          if err is not None and err != '':
            logging.warning('nb remove STDERR: ' + err.strip())

  def getStatus(self):
    """Get the status of the process. Will be called periodically (can be called
    before start). Returns either None, or an object {'id': <any>, 'state':
    <str>, 'runtime_s': <int>, 'memory_mb': <int>}, object values can also be
    None"""
    if self._jobid is not None:
      state = 'UNKNOWN'
      runtime_s = None
      memory_mb = None
      nbstatusExe = self._exeInSameDir(self._config['nb_exe'], 'nbstatus')
      command = [] + nbstatusExe + ['jobs', '--timeout', '60', '--format', 'script', '--fields', 'jobid,status,workstation,task', '--target'] + self._config['target'] + ['jobid={jobid}'.format(jobid=self._jobid)]
      logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command)))
      process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      outs, errs = process.communicate()
      if errs is not None:
        err = errs.decode('utf-8').strip()
        if err != '':
          logging.warning('nbstatus STDERR: ' + err.strip())
      if outs is not None:
        out = outs.decode('utf-8').strip().split(',')
        if len(out) == 4:
          state = out[1]
          self._failedStatusCount = 0
        else:
          command = [] + nbstatusExe + ['jobs', '--format', 'script', '--history', '4m', '--target'] + self._config['target']
          logging.debug('Executing {command}'.format(command=DistManager.shlexJoin(command)))
          process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
          outs, errs = process.communicate()
          if errs is not None:
            err = errs.decode('utf-8').strip()
            if err != '':
              logging.warning('nbstatus STDERR: ' + err.strip())
          if outs is not None:
            out = outs.decode('utf-8').strip()
            if self._jobid in out:
              state = 'Comp'
            else:
              logging.warning('Unable to find job via nbstatus, marking as Exit')
              state = 'Exit'
            self._failedStatusCount = 0
          else:
            self._failedStatusCount += 1
            if self._failedStatusCount > 3:
              self._finish()
        if state in ['Susp', 'Exit', 'Comp', 'Del']:
          if self._returnCode is None:
            # Default an exit status if not set
            if state in ['Susp', 'Exit']:
              self._returnCode = 1
            else:
              self._returnCode = 0
          self._finish()
      else:
        self._failedStatusCount += 1
        if self._failedStatusCount > 3:
          self._finish()
      return {
        'id': self._jobid,
        'state': state,
        'runtime_s': runtime_s,
        'memory_mb': memory_mb
      }
    elif self._submitting:
      self._failedStatusCount = 0
      return {
        'id': None,
        'state': 'SUBMITTING',
        'runtime_s': None,
        'memory_mb': None
      }
    else:
      self._failedStatusCount += 1
      if self._failedStatusCount > 3:
        self._finish()
      return None

  def getResult(self, forceFullReport=False, generateFullReportOnError=False):
    """Get the result of the process. Returns either None or an object
    {'status': <int>, 'stderr': <str>, 'report': <str>}, object values can also
    be None"""
    if self._jobid is not None or self._returnCode is not None:
      return {
        'status': self._returnCode,
        'stderr': self._errs,
        'report': None
      }
    else:
      return None
DistManager.registerMethod('nb', DistNb)

if __name__ == "__main__":
  DistManager(sys.argv)

