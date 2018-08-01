#!/bin/bash
#### THIS FILE IS AUTOMATICALLY GENERATED BY test_generator.sh ###
#### $ bash test_generator.sh 2,4,10,30,40,44,45 > <THIS FILE>

# Directory name of this file
readonly THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%N}}")" && pwd)"
readonly TEST_TMP="${THIS_DIR}/test_tmp"
readonly OLD_PATH="${PATH}"

# func 0 -- Restore old PATH.
# func 1 -- make PATH include tmux.
switch_tmux_path () {
  local _flag="${1:-0}"
  local _tmux_path="${2:-${TRAVIS_BUILD_DIR}/tmp/bin}"

  # --------------------
  # Testing for TravisCI
  # --------------------
  if [[ "${_flag}" -eq 0 ]]; then
    # Remove tmux from the PATH
    export PATH="${OLD_PATH}"
  elif [[ "${_flag}" -eq 1 ]]; then
    if type tmux &> /dev/null;then
      return 0
    fi
    # Make PATH include tmux
    export PATH="${_tmux_path}:${PATH}"
  fi
  return 0
}

tmux_version_number() {
    local _tmux_version=""
    if ! ${TMUX_EXEC} -V &> /dev/null; then
        # From tmux 0.9 to 1.3, there is no -V option.
        # Adjust all to 0.9
        _tmux_version="tmux 0.9"
    else
        _tmux_version="$(${TMUX_EXEC} -V)"
    fi
    echo "${_tmux_version}" | perl -anle 'printf $F[1]'
}

# Check whether the given version is less than current tmux version.
# In case of tmux version is 1.7, the result will be like this.
##  arg  -> result
#   1.5  -> 1
#   1.6  -> 1
#   1.7  -> 1
#   1.8  -> 0
#   1.9  -> 0
#   1.9a -> 0
#   2.0  -> 0
is_less_than() {
    # Simple numerical comparison does not work because there is the version like "1.9a".
    if [[ "$( (tmux_version_number; echo; echo "$1") | sort -n | head -n 1)" != "$1" ]];then
        return 0
    else
        return 1
    fi
}

# !!Run this function at first!!
check_version() {
    switch_tmux_path 1
    local _exec="${BIN_DIR}${EXEC}"
    ${_exec} --dry-run A
    # If tmux version is less than 1.8, skip rest of the tests.
    if is_less_than "1.8" ;then
        echo "Skip rest of the tests." >&2
        echo "Because this version is out of support." >&2
        exit 0
    fi
    switch_tmux_path 0
}

create_tmux_session() {
    local _socket_file="$1"
    ${TMUX_EXEC} -S "${_socket_file}" new-session -d
    # Once attach tmux session and detach it.
    # Because, pipe-pane feature does not work with tmux 1.8 (it might be bug).
    # To run pipe-pane, it is necessary to attach the session.
    ${TMUX_EXEC} -S "${_socket_file}" send-keys "sleep 1 && ${TMUX_EXEC} detach-client" C-m
    ${TMUX_EXEC} -S "${_socket_file}" attach-session
}

is_allow_rename_value_on() {
  local _socket_file="${THIS_DIR}/.xpanes-shunit"
  local _value_allow_rename
  local _value_automatic_rename
  create_tmux_session "${_socket_file}"
  _value_allow_rename="$(${TMUX_EXEC} -S "${_socket_file}" show-window-options -g | awk '$1=="allow-rename"{print $2}')"
  _value_automatic_rename="$(${TMUX_EXEC} -S "${_socket_file}" show-window-options -g | awk '$1=="automatic-rename"{print $2}')"
  close_tmux_session "${_socket_file}"
  if [ "${_value_allow_rename}" = "on" ] ;then
    return 0
  fi
  if [ "${_value_automatic_rename}" = "on" ] ;then
    return 0
  fi
  return 1
}

exec_tmux_session() {
    local _socket_file="$1" ;shift
    # local _tmpdir=${SHUNIT_TMPDIR:-/tmp}
    # echo "send-keys: cd ${BIN_DIR} && $* && touch ${SHUNIT_TMPDIR}/done" >&2
    # Same reason as the comments near "create_tmux_session".
    ${TMUX_EXEC} -S "${_socket_file}" send-keys "cd ${BIN_DIR} && $* && touch ${SHUNIT_TMPDIR}/done && sleep 1 && ${TMUX_EXEC} detach-client" C-m
    ${TMUX_EXEC} -S "${_socket_file}" attach-session
    # Wait until tmux session is completely established.
    for i in $(seq 30) ;do
        # echo "exec_tmux_session: wait ${i} sec..."
        sleep 1
        if [ -e "${SHUNIT_TMPDIR}/done" ]; then
            rm -f "${SHUNIT_TMPDIR}/done"
            break
        fi
        # Tmux session does not work.
        if [ "${i}" -eq 30 ]; then
            echo "Tmux session timeout" >&2
            return 1
        fi
    done
}

capture_tmux_session() {
    local _socket_file="$1"
    ${TMUX_EXEC} -S "${_socket_file}" capture-pane
    ${TMUX_EXEC} -S "${_socket_file}" show-buffer
}

close_tmux_session() {
    local _socket_file="$1"
    ${TMUX_EXEC} -S "${_socket_file}" kill-session
    rm "${_socket_file}"
}

wait_panes_separation() {
    local _socket_file="$1"
    local _window_name_prefix="$2"
    local _expected_pane_num="$3"
    local _window_id=""
    local _pane_num=""
    local _wait_seconds=30
    # Wait until pane separation is completed
    for i in $(seq "${_wait_seconds}") ;do
        sleep 1
        ## tmux bug: tmux does not handle the window_name which has dot(.) at the begining of the name. Use window_id instead.
        _window_id=$(${TMUX_EXEC} -S "${_socket_file}" list-windows -F '#{window_name} #{window_id}' \
          | grep "^${_window_name_prefix}" \
          | head -n 1 \
          | perl -anle 'print $F[$#F]')
        printf "%s\\n" "wait_panes_separation: ${i} sec..." >&2
        ${TMUX_EXEC} -S "${_socket_file}" list-windows -F '#{window_name} #{window_id}' >&2
        printf "_window_id:[%s]\\n" "${_window_id}"
        if [ -n "${_window_id}" ]; then
            # ${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_id}"
            _pane_num="$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_id}" | grep -c .)"
            # tmux -S "${_socket_file}" list-panes -t "${_window_name}"
            if [ "${_pane_num}" = "${_expected_pane_num}" ]; then
                ${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_id}" >&2
                # Wait several seconds to ensure the completion.
                # Even the number of panes equals to expected number,
                # the separation is not complated sometimes.
                sleep 3
                break
            fi
        fi
        # Still not separated.
        if [ "${i}" -eq "${_wait_seconds}" ]; then
            fail "wait_panes_separation: Too long time for window separation. Aborted." >&2
            return 1
        fi
    done
    return 0
}

wait_all_files_creation(){
    local _wait_seconds=30
    local _break=1
    # Wait until specific files are created.
    for i in $(seq "${_wait_seconds}") ;do
        sleep 1
        _break=1
        for f in "$@" ;do
            if ! [ -e "${f}" ]; then
                # echo "${f}:does not exist." >&2
                _break=0
            fi
        done
        if [ "${_break}" -eq 1 ]; then
            break
        fi
        if [ "${i}" -eq "${_wait_seconds}" ]; then
            echo "wait_all_files_creation: Test failed" >&2
            return 1
        fi
    done
    return 0
}

wait_existing_file_number(){
    local _target_dir="$1"
    local _expected_num="$2"
    local _num_of_files=0
    local _wait_seconds=30
    # Wait until specific number of files are created.
    for i in $(seq "${_wait_seconds}") ;do
        sleep 1
        _num_of_files=$(printf "%s\\n" "${_target_dir}"/* | grep -c .)
        if [ "${_num_of_files}" = "${_expected_num}" ]; then
            break
        fi
        if [ "${i}" -eq "${_wait_seconds}" ]; then
            echo "wait_existing_file_number: Test failed" >&2
            return 1
        fi
    done
    return 0
}

all_non_empty_files(){
    local _count=0
    for f in "$@";do
      # if the file is non empty
      if [ -s "$f" ]; then
        _count=$(( _count + 1 ))
      else
        echo "all_non_empty_files: $f is still empty" >&2
      fi
    done
    if [[ $_count -eq $# ]]; then
      # echo "all_non_empty_files:non empty: $*" >&2
      return 0
    fi
    return 1
}

wait_all_non_empty_files(){
    local _num_of_files=0
    local _wait_seconds=5
    # Wait until specific number of files are created.
    for i in $(seq "${_wait_seconds}") ;do
        if all_non_empty_files "$@"; then
            break
        fi
        if [ "${i}" -eq "${_wait_seconds}" ]; then
            echo "wait_all_non_empty_files: Test failed" >&2
            return 1
        fi
        sleep 1
    done
    return 0
}

between_plus_minus() {
    local _range="$1"
    shift
    echo "$(( ( $1 + _range ) >= $2 && $2 >= ( $1 - _range ) ))"
}

# Returns the index of the window and number of it's panes.
# The reason why it does not use #{window_panes} is, tmux 1.6 does not support the format.
get_window_having_panes() {
  local _socket_file="$1"
  local _pane_num="$2"
  while read -r idx;
  do
    echo -n "${idx} "; ${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${idx}" -F '#{pane_index}' | grep -c .
  done < <(${TMUX_EXEC}  -S "${_socket_file}" list-windows -F '#{window_index}') \
    | awk '$2==pane_num{print $1}' pane_num="${_pane_num}" | head -n 1
}

divide_two_panes_impl() {
    local _socket_file="$1"
    local _window_name=""
    _window_name=$(get_window_having_panes "${_socket_file}" "2")

    # Window should be divided like this.
    # +---+---+
    # | A | B |
    # +---+---+

    echo "Check number of panes"
    assertEquals 2 "$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" | grep -c .)"

    echo "Check width"
    a_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==1')
    b_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==2')
    echo "A:${a_width} B:${b_width}"
    # true:1, false:0
    # a_width +- 1 is b_width
    assertEquals 1 "$(between_plus_minus 1 "${a_width}" "${b_width}")"

    echo "Check height"
    a_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==1')
    b_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==2')
    echo "A:${a_height} B:${b_height}"
    # In this case, height must be same.
    assertEquals 1 "$(( a_height == b_height ))"
}

divide_three_panes_impl() {
    local _socket_file="$1"
    local _window_name=""
    _window_name=$(get_window_having_panes "${_socket_file}" "3")

    # Window should be divided like this.
    # +---+---+
    # | A | B |
    # +---+---+
    # |   C   |
    # +---+---+

    echo "Check number of panes"
    assertEquals 3 "$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" | grep -c .)"

    echo "Check width"
    a_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==1')
    b_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==2')
    c_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==3')
    echo "A:${a_width} B:${b_width} C:${c_width}"
    assertEquals 1 "$(between_plus_minus 1 "${a_width}" "${b_width}")"
    assertEquals 1 "$(( $(( a_width + b_width + 1 )) == c_width ))"

    echo "Check height"
    a_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==1')
    b_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==2')
    c_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==3')
    echo "A:${a_height} B:${b_height} C:${c_height}"
    # In this case, height must be same.
    assertEquals 1 "$(( a_height == b_height ))"
    assertEquals 1 "$(between_plus_minus 1 "${c_height}" "${a_height}")"
}

divide_four_panes_impl() {
    local _socket_file="$1"
    local _window_name=""
    _window_name=$(get_window_having_panes "${_socket_file}" "4")

    # Window should be divided like this.
    # +---+---+
    # | A | B |
    # +---+---+
    # | C | D |
    # +---+---+

    echo "Check width"
    a_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==1')
    b_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==2')
    c_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==3')
    d_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==4')
    echo "A:${a_width} B:${b_width} C:${c_width} D:${d_width}"

    assertEquals 1 "$((a_width == c_width))"
    assertEquals 1 "$((b_width == d_width))"
    assertEquals 1 "$(between_plus_minus 1 "${a_width}" "${b_width}")"
    assertEquals 1 "$(between_plus_minus 1 "${c_width}" "${d_width}")"

    echo "Check height"
    a_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==1')
    b_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==2')
    c_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==3')
    d_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==4')
    echo "A:${a_height} B:${b_height} C:${c_height} D:${d_height}"
    # In this case, height must be same.
    assertEquals 1 "$(( a_height == b_height ))"
    assertEquals 1 "$(( c_height == d_height ))"
    assertEquals 1 "$(between_plus_minus 1 "${a_height}" "${c_height}")"
    assertEquals 1 "$(between_plus_minus 1 "${b_height}" "${d_height}")"
}

divide_five_panes_impl() {
    local _socket_file="$1"
    local _window_name=""
    _window_name=$(get_window_having_panes "${_socket_file}" "5")

    # Window should be divided like this.
    # +---+---+
    # | A | B |
    # +---+---+
    # | C | D |
    # +---+---+
    # |   E   |
    # +---+---+

    echo "Check width"
    a_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==1')
    b_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==2')
    c_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==3')
    d_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==4')
    e_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==5')
    echo "A:${a_width} B:${b_width} C:${c_width} D:${d_width} E:${e_width}"
    assertEquals 1 "$((a_width == c_width))"
    assertEquals 1 "$((b_width == d_width))"
    assertEquals 1 "$(between_plus_minus 1 "${a_width}" "${b_width}")"
    assertEquals 1 "$(between_plus_minus 1 "${c_width}" "${d_width}")"
    # Width of A + B is greater than E with 1 px. Because of the border.
    assertEquals 1 "$(( $(( a_width + b_width + 1 )) == e_width))"

    echo "Check height"
    a_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==1')
    b_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==2')
    c_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==3')
    d_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==4')
    e_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==5')
    echo "A:${a_height} B:${b_height} C:${c_height} D:${d_height} E:${e_height}"
    assertEquals 1 "$(( a_height == b_height ))"
    assertEquals 1 "$(( c_height == d_height ))"
    assertEquals 1 "$(between_plus_minus 1 "${a_height}" "${c_height}")"
    assertEquals 1 "$(between_plus_minus 1 "${b_height}" "${d_height}")"
    # On author's machine, following two tests does not pass with 1 ... somehow.
    assertEquals 1 "$(between_plus_minus 2 "${a_height}" "${e_height}")"
    assertEquals 1 "$(between_plus_minus 2 "${c_height}" "${e_height}")"
}

divide_two_panes_ev_impl() {
    local _socket_file="$1"
    local _window_name=""
    _window_name=$(get_window_having_panes "${_socket_file}" "2")

    # Window should be divided like this.
    # +-------+
    # |   A   |
    # +-------+
    # |   B   |
    # +-------+

    echo "Check number of panes"
    assertEquals 2 "$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" | grep -c .)"

    echo "Check width"
    a_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==1')
    b_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==2')
    echo "A:${a_width} B:${b_width}"
    # true:1, false:0
    # In this case, height must be same.
    assertEquals 1 "$(( a_width == b_width ))"

    echo "Check height"
    a_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==1')
    b_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==2')
    echo "A:${a_height} B:${b_height}"
    # a_height +- 1 is b_height
    assertEquals 1 "$(between_plus_minus 1 "${a_height}" "${b_height}")"
}

divide_two_panes_eh_impl() {
    divide_two_panes_impl "$1"
}

divide_three_panes_ev_impl() {
    local _socket_file="$1"
    local _window_name=""
    _window_name=$(get_window_having_panes "${_socket_file}" "3")

    # Window should be divided like this.
    # +-------+
    # |   A   |
    # +-------+
    # |   B   |
    # +-------+
    # |   C   |
    # +-------+

    echo "Check number of panes"
    assertEquals 3 "$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" | grep -c .)"

    echo "Check width"
    a_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==1')
    b_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==2')
    c_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==3')
    echo "A:${a_width} B:${b_width} C:${c_width}"
    # true:1, false:0
    # In this case, height must be same.
    assertEquals 1 "$(( a_width == b_width ))"
    assertEquals 1 "$(( b_width == c_width ))"

    echo "Check height"
    a_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==1')
    b_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==2')
    c_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==3')
    echo "A:${a_height} B:${b_height} C:${c_height}"

    assertEquals 1 "$(between_plus_minus 1 "${a_height}" "${b_height}")"
    assertEquals 1 "$(between_plus_minus 2 "${b_height}" "${c_height}")"
}

divide_three_panes_eh_impl() {
    local _socket_file="$1"
    local _window_name=""
    _window_name=$(get_window_having_panes "${_socket_file}" "3")

    # Window should be divided like this.
    # +---+---+---+
    # | A | B | C |
    # +---+---+---+

    echo "Check number of panes"
    assertEquals 3 "$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" | grep -c .)"

    echo "Check width"
    a_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==1')
    b_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==2')
    c_width=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_width}' | awk 'NR==3')
    echo "A:${a_width} B:${b_width} C:${c_width}"
    # true:1, false:0
    # In this case, height must be same.
    assertEquals 1 "$(between_plus_minus 1 "${a_width}" "${b_width}")"
    assertEquals 1 "$(between_plus_minus 2 "${b_width}" "${c_width}")"

    echo "Check height"
    a_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==1')
    b_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==2')
    c_height=$(${TMUX_EXEC} -S "${_socket_file}" list-panes -t "${_window_name}" -F '#{pane_height}' | awk 'NR==3')
    echo "A:${a_height} B:${b_height} C:${c_height}"

    assertEquals 1 "$(( a_height == b_height ))"
    assertEquals 1 "$(( b_height == c_height ))"
}

get_tmux_full_path () {
  switch_tmux_path 1
  command -v tmux
  switch_tmux_path 0
}

set_tmux_exec_randomly () {
  local _num
  local _exec
  _num=$((RANDOM % 4));
  _exec="$(get_tmux_full_path)"

  if [[ ${_num} -eq 0 ]];then
    export TMUX_XPANES_EXEC="${_exec} -2"
    switch_tmux_path 0
  elif [[ ${_num} -eq 1 ]];then
    export TMUX_XPANES_EXEC="${_exec}"
    switch_tmux_path 0
  elif [[ ${_num} -eq 2 ]];then
    unset TMUX_XPANES_EXEC
    switch_tmux_path 1
  elif [[ ${_num} -eq 3 ]];then
    export TMUX_XPANES_EXEC="tmux -2"
    switch_tmux_path 1
  fi
}

setUp(){
    cd "${BIN_DIR}" || exit
    mkdir -p "${TEST_TMP}"
    set_tmux_exec_randomly
    echo ">>>>>>>>>>" >&2
    echo "TMUX_XPANES_EXEC ... '${TMUX_XPANES_EXEC}'" >&2
}

tearDown(){
    rm -rf "${TEST_TMP}"
    echo "<<<<<<<<<<" >&2
    echo >&2
}


###:-:-:INSERT_TESTING:-:-:###
# @case: 2
# @skip: 1.8,2.3
test_normalize_log_directory() {
    if [ "$(tmux_version_number)" == "1.8" ] ;then
        echo "Skip this test for $(${TMUX_EXEC} -V)." >&2
        echo "Because of following reasons." >&2
        echo "1. Logging feature does not work when tmux version 1.8 and tmux session is NOT attached. " >&2
        echo "2. If standard input is NOT a terminal, tmux session is NOT attached." >&2
        echo "3. As of March 2017, macOS machines on Travis CI does not have a terminal." >&2
        return 0
    fi
    if [[ "$(tmux_version_number)" == "2.3" ]];then
        echo "Skip this test for $(${TMUX_EXEC} -V)." >&2
        echo "Because of the bug (https://github.com/tmux/tmux/issues/594)." >&2
        return 0
    fi

    local _socket_file="${SHUNIT_TMPDIR}/.xpanes-shunit"
    local _cmd=""
    local _log_file=""
    local _tmpdir="${SHUNIT_TMPDIR}"
    local _homebak="${HOME}"

    mkdir -p "${_tmpdir}/fin"
    _cmd="export HOME=${_tmpdir}; ${EXEC} --log=~/logs/ -I@ -S ${_socket_file} -c\"echo HOGE_@_ | sed s/HOGE/GEGE/ &&touch ${_tmpdir}/fin/@ && ${TMUX_EXEC} detach-client\" AAAA AAAA BBBB"
    printf "\\n%s\\n" "$ ${_cmd}"
    eval "${_cmd}"
    # Restore home
    export HOME="${_homebak}"
    wait_panes_separation "${_socket_file}" "AAAA" "3"
    wait_existing_file_number "${_tmpdir}/fin" "2"

    # Wait several seconds just in case.
    sleep 3
    printf "%s\\n" "${_tmpdir}"/logs/* | grep -E 'AAAA-1\.log\..*$'
    assertEquals 0 $?
    _log_file=$(printf "%s\\n" "${_tmpdir}"/logs/* | grep -E 'AAAA-1\.log\..*$')
    assertEquals 1 "$(grep -ac 'GEGE_AAAA_' < "${_log_file}")"

    printf "%s\\n" "${_tmpdir}"/logs/* | grep -E 'AAAA-2\.log\..*$'
    assertEquals 0 $?
    _log_file=$(printf "%s\\n" "${_tmpdir}"/logs/* | grep -E 'AAAA-2\.log\..*$')
    assertEquals 1 "$(grep -ac 'GEGE_AAAA_' < "${_log_file}")"

    printf "%s\\n" "${_tmpdir}"/logs/* | grep -E 'BBBB-1\.log\..*$'
    assertEquals 0 $?
    _log_file=$(printf "%s\\n" "${_tmpdir}"/logs/* | grep -E 'BBBB-1\.log\..*$')
    assertEquals 1 "$(grep -ac 'GEGE_BBBB_' < "${_log_file}")"

    close_tmux_session "${_socket_file}"
    rm -f "${_tmpdir}"/logs/*
    rmdir "${_tmpdir}"/logs
    rm -f "${_tmpdir}"/fin/*
    rmdir "${_tmpdir}"/fin

    : "In TMUX session" && {
        printf "\\n%s\\n" "$ TMUX(${_cmd})"
        mkdir -p "${_tmpdir}/fin"

        create_tmux_session "${_socket_file}"
        exec_tmux_session "${_socket_file}" "${_cmd}"
        wait_panes_separation "${_socket_file}" "AAAA" "3"
        wait_existing_file_number "${_tmpdir}/fin" "2"

        # Wait several seconds just in case.
        sleep 3
        printf "%s\\n" "${_tmpdir}"/logs/* | grep -E 'AAAA-1\.log\..*$'
        assertEquals 0 $?
        _log_file=$(printf "%s\\n" "${_tmpdir}"/logs/* | grep -E 'AAAA-1\.log\..*$')
        assertEquals 1 "$( grep -ac 'GEGE_AAAA_' < "${_log_file}" )"

        printf "%s\\n" "${_tmpdir}"/logs/* | grep -E 'AAAA-2\.log\..*$'
        assertEquals 0 $?
        _log_file=$(printf "%s\\n" "${_tmpdir}"/logs/* | grep -E 'AAAA-2\.log\..*$')
        assertEquals 1 "$( grep -ac 'GEGE_AAAA_' < "${_log_file}" )"

        printf "%s\\n" "${_tmpdir}"/logs/* | grep -E 'BBBB-1\.log\..*$'
        assertEquals 0 $?
        _log_file=$(printf "%s\\n" "${_tmpdir}"/logs/* | grep -E 'BBBB-1\.log\..*$')
        assertEquals 1 "$( grep -ac 'GEGE_BBBB_' < "${_log_file}" )"

        close_tmux_session "${_socket_file}"

        rm -f "${_tmpdir}"/logs/*
        rmdir "${_tmpdir}"/logs
        rm -f "${_tmpdir}"/fin/*
        rmdir "${_tmpdir}"/fin
    }
}
# @case: 4
# @skip:
test_window_name_having_special_chars() {
    local _socket_file="${SHUNIT_TMPDIR}/.xpanes-shunit"
    local _cmd=""

    local _expected_name='%.-&*_.co.jp'
    local _actual_name=""
    _cmd="${EXEC} -S $_socket_file --stay '$_expected_name'"
    printf "\\n $ %s\\n" "$_cmd"
    # ${TMUX_EXEC} -S "$_socket_file" set-window-option -g allow-rename off
    eval "$_cmd"
    wait_panes_separation "$_socket_file" "%" '1'
    _actual_name=$(${TMUX_EXEC} -S "$_socket_file" list-windows -F '#{window_name}' | grep '%' | perl -pe 's/-[0-9]+$//g')
    close_tmux_session "$_socket_file"
    echo "Actual name:$_actual_name Expected name:$_expected_name"
    assertEquals "$_expected_name" "$_actual_name"

    : "In TMUX session" && {
        _cmd="${EXEC} -S $_socket_file '$_expected_name'"
        printf "\\n $ TMUX(%s)\\n" "$_cmd"
        create_tmux_session "$_socket_file"
        ${TMUX_EXEC} -S "$_socket_file" set-window-option -g allow-rename off
        exec_tmux_session "$_socket_file" "$_cmd"
        wait_panes_separation "$_socket_file" "%" '1'
        _actual_name=$(${TMUX_EXEC} -S "$_socket_file" list-windows -F '#{window_name}' | grep '%' | perl -pe 's/-[0-9]+$//g')
        close_tmux_session "$_socket_file"
        echo "Actual name:$_actual_name Expected name:$_expected_name"
        assertEquals "$_expected_name" "$_actual_name"
    }
}
# @case: 10
# @skip:
test_keep_allow_rename_opt() {
    local _socket_file="${SHUNIT_TMPDIR}/.xpanes-shunit"
    local _cmd=""
    local _allow_rename_status=""

    _cmd="${EXEC} -S $_socket_file AA BB CC DD EE"
    : "In TMUX session" && {

        # allow-rename on
        printf "\\nTMUX(%s)\\n" "${_cmd}"
        create_tmux_session "$_socket_file"
        ${TMUX_EXEC} -S "$_socket_file" set-window-option -g allow-rename on
        echo "allow-rename(before): on"
        exec_tmux_session "$_socket_file" "$_cmd"
        wait_panes_separation "$_socket_file" "AA" "5"
        _allow_rename_status="$(${TMUX_EXEC} -S "$_socket_file" show-window-options -g | awk '$1=="allow-rename"{print $2}')"
        echo "allow-rename(after): $_allow_rename_status"
        assertEquals "on" "$_allow_rename_status"
        close_tmux_session "$_socket_file"

        # allow-rename off
        printf "\\nTMUX(%s)\\n" "${_cmd}"
        create_tmux_session "$_socket_file"
        ${TMUX_EXEC} -S "$_socket_file" set-window-option -g allow-rename off
        echo "allow-rename(before): off"
        exec_tmux_session "$_socket_file" "$_cmd"
        wait_panes_separation "$_socket_file" "AA" "5"
        _allow_rename_status="$(${TMUX_EXEC} -S "$_socket_file" show-window-options -g | awk '$1=="allow-rename"{print $2}')"
        echo "allow-rename(after): $_allow_rename_status"
        assertEquals "off" "$_allow_rename_status"
        close_tmux_session "$_socket_file"
    }
}
# @case: 30
# @skip:
test_hyphen_and_option2() {
    local _socket_file="${SHUNIT_TMPDIR}/.xpanes-shunit"
    local _cmd=""
    local _tmpdir="${SHUNIT_TMPDIR}"

    _cmd="${EXEC} -I@ -S $_socket_file -c \"cat <<<@ > ${_tmpdir}/@.result\" --stay -- -- AA --Z BB"
    printf "\\n$ %s\\n" "${_cmd}"
    ${EXEC} -I@ -S "${_socket_file}" -c "cat <<<@ > ${_tmpdir}/@.result" --stay -- -- AA --Z BB
    wait_panes_separation "$_socket_file" "--" "4"
    wait_all_files_creation "${_tmpdir}"/{--,AA,--Z,BB}.result
    diff "${_tmpdir}/--.result" <(cat <<<--)
    assertEquals 0 $?
    diff "${_tmpdir}/AA.result" <(cat <<<AA)
    assertEquals 0 $?
    diff "${_tmpdir}/--Z.result" <(cat <<<--Z)
    assertEquals 0 $?
    diff "${_tmpdir}/BB.result" <(cat <<<BB)
    assertEquals 0 $?
    close_tmux_session "$_socket_file"
    rm -f "${_tmpdir:?}"/*.result

    : "In TMUX session" && {
        printf "\\nTMUX(%s)\\n" "${_cmd}"
        create_tmux_session "$_socket_file"
        exec_tmux_session "$_socket_file" "$_cmd"
        wait_panes_separation "$_socket_file" "--" "4"
        wait_all_files_creation "${_tmpdir}"/{--,AA,--Z,BB}.result
        diff "${_tmpdir}/--.result" <(cat <<<--)
        assertEquals 0 $?
        diff "${_tmpdir}/AA.result" <(cat <<<AA)
        assertEquals 0 $?
        diff "${_tmpdir}/--Z.result" <(cat <<<--Z)
        assertEquals 0 $?
        diff "${_tmpdir}/BB.result" <(cat <<<BB)
        assertEquals 0 $?
        close_tmux_session "$_socket_file"
        rm -f "${_tmpdir:?}"/*.result
    }
}
# @case: 40
# @skip:
test_divide_three_panes() {
    local _socket_file="${SHUNIT_TMPDIR}/.xpanes-shunit"
    local _cmd=""

    _cmd="${EXEC} -S $_socket_file --stay AAAA BBBB CCCC"
    printf "\\n$ %s\\n" "${_cmd}"
    eval "$_cmd"
    wait_panes_separation "$_socket_file" "AAAA" "3"
    divide_three_panes_impl "$_socket_file"
    close_tmux_session "$_socket_file"

    : "In TMUX session" && {
        printf "\\nTMUX(%s)\\n" "${_cmd}"
        create_tmux_session "$_socket_file"
        exec_tmux_session "$_socket_file" "$_cmd"
        wait_panes_separation "$_socket_file" "AAAA" "3"
        divide_three_panes_impl "$_socket_file"
        close_tmux_session "$_socket_file"
    }
}
# @case: 44
# @skip:
test_divide_five_panes() {
    local _socket_file="${SHUNIT_TMPDIR}/.xpanes-shunit"
    local _cmd=""

    _cmd="${EXEC} -S $_socket_file --stay AAAA BBBB CCCC DDDD EEEE"
    printf "\\n$ %s\\n" "${_cmd}"
    eval "$_cmd"
    wait_panes_separation "$_socket_file" "AAAA" "5"
    divide_five_panes_impl "$_socket_file"
    close_tmux_session "$_socket_file"

    : "In TMUX session" && {
        printf "\\nTMUX(%s)\\n" "${_cmd}"
        create_tmux_session "$_socket_file"
        exec_tmux_session "$_socket_file" "$_cmd"
        wait_panes_separation "$_socket_file" "AAAA" "5"
        divide_five_panes_impl "$_socket_file"
        close_tmux_session "$_socket_file"
    }
}
# @case: 45
# @skip:
test_divide_five_panes_pipe() {
    local _socket_file="${SHUNIT_TMPDIR}/.xpanes-shunit"
    local _cmd=""

    _cmd="echo AAAA BBBB CCCC DDDD EEEE | xargs -n 1 | ${EXEC} -S $_socket_file"
    printf "\\n$ %s\\n" "${_cmd}"
    eval "$_cmd"
    wait_panes_separation "$_socket_file" "AAAA" "5"
    divide_five_panes_impl "$_socket_file"
    close_tmux_session "$_socket_file"

    : "In TMUX session" && {
        printf "\\nTMUX(%s)\\n" "${_cmd}"
        _cmd="echo AAAA BBBB CCCC DDDD EEEE | xargs -n 1 | ${EXEC}"
        create_tmux_session "$_socket_file"
        exec_tmux_session "$_socket_file" "$_cmd"
        wait_panes_separation "$_socket_file" "AAAA" "5"
        divide_five_panes_impl "$_socket_file"
        close_tmux_session "$_socket_file"
    }
}

readonly TMUX_EXEC=$(get_tmux_full_path)
if [ -n "$BASH_VERSION" ]; then
  # This is bash
  echo "Testing for bash $BASH_VERSION"
  echo "tmux path: ${TMUX_EXEC}"
  echo "            $(${TMUX_EXEC} -V)"
  echo
fi

if [ -n "$TMUX" ]; then
 echo "[Error] Do NOT execute this test inside of TMUX session." >&2
 exit 1
fi

if [ -n "$TMUX_XPANES_LOG_FORMAT" ]; then
 echo "[Warning] TMUX_XPANES_LOG_FORMAT is defined." >&2
 echo "During the test, this variable is updated." >&2
 echo "    Executed: export TMUX_XPANES_LOG_FORMAT=" >&2
 echo "" >&2
 export TMUX_XPANES_LOG_FORMAT=
fi

if [ -n "$TMUX_XPANES_LOG_DIRECTORY" ]; then
 echo "[Warning] TMUX_XPANES_LOG_DIRECTORY is defined." >&2
 echo "During the test, this variable is updated." >&2
 echo "    Executed: export TMUX_XPANES_LOG_DIRECTORY=" >&2
 echo "" >&2
 export TMUX_XPANES_LOG_DIRECTORY=
fi


if is_allow_rename_value_on; then
  echo "[Error] tmux's 'allow-rename' or 'automatic-rename' window option is now 'on'." >&2
  echo "Please make it off before starting testing." >&2
  echo "Execute this:
    echo 'set-window-option -g allow-rename off' >> ~/.tmux.conf
    echo 'set-window-option -g automatic-rename off' >> ~/.tmux.conf" >&2
  exit 1
fi

BIN_DIR="${THIS_DIR}/../bin/"
# Get repository name which equals to bin name.
# BIN_NAME="$(basename $(git rev-parse --show-toplevel))"
BIN_NAME="xpanes"
EXEC="./${BIN_NAME}"
check_version

# Test start
# shellcheck source=/dev/null
. "${THIS_DIR}/shunit2/source/2.1/src/shunit2"
