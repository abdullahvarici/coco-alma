#!/bin/bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Script to update labels file

cp tmp/labels.txt tmp/labels-updated.txt

core=$1

input_label_file=$2

while read -r line
do
    IFS=":" read -ra arr <<< "$line"
    regnum=${arr[0]}
    regbitnum=$(($regnum * 32))
    label=${arr[1]}

    if [ $1 == "otbn" ]
    then
        sed -n "/u_dmem\.mem\[$regnum\]:0:.*: unimportant/ s/unimportant/$label/p" tmp/labels-updated.txt
        sed -i "/u_dmem\.mem\[$regnum\]:0:.*: unimportant/ s/unimportant/$label/" tmp/labels-updated.txt
    elif [ $1 == "ibex" ]
    then
        sed -n "/u_core\.register_file_i\.rf_reg:$regbitnum:.*: unimportant/ s/unimportant/$label/p" tmp/labels-updated.txt
        sed -i "/u_core\.register_file_i\.rf_reg:$regbitnum:.*: unimportant/ s/unimportant/$label/" tmp/labels-updated.txt
    fi
    
done < "${input_label_file}"